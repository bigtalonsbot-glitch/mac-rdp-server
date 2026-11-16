#!/usr/bin/env bash
# Mac RDP Server — installs xrdp and bridges it to macOS Screen Sharing
# Windows users connect with mstsc.exe to this Mac's IP on port 3389.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="/opt/mac-rdp"
XRDP_SRC="$SCRIPT_DIR/build/xrdp"
XRDP_VER="0.9.24"
LOG="$SCRIPT_DIR/install.log"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GRN}[+]${NC} $*"; }
warn()  { echo -e "${YLW}[!]${NC} $*"; }
die()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
log()   { echo "$*" >> "$LOG"; }

banner() {
cat <<'EOF'
  __  __            ____  ____  ____     ____
 |  \/  | __ _  ___|  _ \|  _ \|  _ \   / ___|  ___ _ ____   _____ _ __
 | |\/| |/ _` |/ __| |_) | | | | |_) |  \___ \ / _ \ '__\ \ / / _ \ '__|
 | |  | | (_| | (__|  _ <| |_| |  __/    ___) |  __/ |   \ V /  __/ |
 |_|  |_|\__,_|\___|_| \_\____/|_|      |____/ \___|_|    \_/ \___|_|

 RDP server for macOS — native Windows Remote Desktop support
EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Run with sudo: sudo bash install.sh"
    fi
}

check_deps() {
    info "Checking dependencies..."
    local missing=()
    command -v brew &>/dev/null || die "Homebrew not found. Install from https://brew.sh"

    for pkg in autoconf automake libtool pkg-config openssl nasm libx11 libxfixes libxrandr; do
        if ! brew list "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        info "Installing build dependencies: ${missing[*]}"
        sudo -u "$SUDO_USER" brew install "${missing[@]}" 2>&1 | tee -a "$LOG"
    fi

    # Xcode Command Line Tools (needed for PAM headers on macOS)
    if ! xcode-select -p &>/dev/null; then
        warn "Xcode Command Line Tools not found — installing..."
        xcode-select --install
        read -rp "Press Enter after CLT installation completes..."
    fi
}

enable_screen_sharing() {
    info "Enabling macOS Screen Sharing (VNC)..."

    # Enable the Screen Sharing service (VNC server on port 5900)
    launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true

    # Screen Sharing password — typed at the RDP login screen.
    # Legacy VNC auth only uses the first 8 characters.
    while :; do
        read -rsp "Choose a remote desktop password (max 8 chars): " VNC_PW </dev/tty; echo
        [[ ${#VNC_PW} -ge 6 ]] && break
        warn "Use at least 6 characters."
    done

    /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
        -activate -configure -access -on \
        -clientopts -setvnclegacy -vnclegacy yes \
        -clientopts -setvncpw -vncpw "$VNC_PW" \
        -restart -agent -privs -all 2>&1 | tee -a "$LOG" || true

    # Fallback: enable via defaults
    defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist \
        com.apple.screensharing -dict Disabled -bool false 2>/dev/null || true

    # Open Screen Sharing firewall port
    /usr/libexec/ApplicationFirewall/socketfilterfw --add /System/Library/CoreServices/ScreenSharingD 2>/dev/null || true

    info "Screen Sharing enabled on port 5900"
}

apply_patches() {
    # Local fixes on top of upstream xrdp (smooth scrolling, etc.)
    local p
    for p in "$SCRIPT_DIR"/patches/*.patch; do
        [[ -e "$p" ]] || continue
        info "Applying $(basename "$p")..."
        patch -p1 --forward < "$p" 2>&1 | tee -a "$LOG" \
            || die "Patch failed: $p"
    done
}

build_xrdp() {
    info "Building xrdp $XRDP_VER from source..."

    mkdir -p "$SCRIPT_DIR/build"
    cd "$SCRIPT_DIR/build"

    if [[ ! -d xrdp ]]; then
        info "Cloning xrdp..."
        git clone --depth 1 --branch "v${XRDP_VER}" \
            https://github.com/neutrinolabs/xrdp.git 2>&1 | tee -a "$LOG"
    fi

    cd xrdp

    # Determine Homebrew prefix (Apple Silicon vs Intel)
    BREW_PREFIX="$(sudo -u "$SUDO_USER" brew --prefix)"
    OPENSSL_PREFIX="$(sudo -u "$SUDO_USER" brew --prefix openssl)"

    # macOS: Homebrew installs libtool as glibtoolize; autoreconf needs libtoolize in PATH
    export PATH="${BREW_PREFIX}/opt/libtool/libexec/gnubin:${BREW_PREFIX}/bin:${PATH}"

    # Reset any partial state from a previous failed run
    git clean -fd 2>&1 | tee -a "$LOG"
    git checkout -- . 2>&1 | tee -a "$LOG"

    apply_patches

    info "Running bootstrap..."
    ./bootstrap 2>&1 | tee -a "$LOG"

    X11_PREFIX="${BREW_PREFIX}/opt/libx11"

    info "Configuring xrdp (VNC-bridge mode)..."
    CFLAGS="-I${BREW_PREFIX}/include -I${X11_PREFIX}/include -I/usr/include" \
    CPPFLAGS="-I${OPENSSL_PREFIX}/include -I${X11_PREFIX}/include" \
    LDFLAGS="-L${OPENSSL_PREFIX}/lib -L${BREW_PREFIX}/lib -L${X11_PREFIX}/lib" \
    PKG_CONFIG_PATH="${OPENSSL_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/lib/pkgconfig:${X11_PREFIX}/lib/pkgconfig" \
    ./configure \
        --prefix="${INSTALL_PREFIX}" \
        --sysconfdir="${INSTALL_PREFIX}/etc" \
        --localstatedir="${INSTALL_PREFIX}/var" \
        --with-openssl="${OPENSSL_PREFIX}" \
        --x-includes="${X11_PREFIX}/include" \
        --x-libraries="${X11_PREFIX}/lib" \
        --disable-ipv6 \
        --disable-debug \
        --disable-xorgxrdp \
        --enable-rfxcodec \
        2>&1 | tee -a "$LOG"

    info "Compiling (this takes ~2-3 minutes)..."
    make -j"$(sysctl -n hw.logicalcpu)" 2>&1 | tee -a "$LOG"

    info "Installing to ${INSTALL_PREFIX}..."
    make install 2>&1 | tee -a "$LOG"

    info "xrdp built and installed successfully"
}

configure_xrdp() {
    info "Configuring xrdp..."

    local cfg_dir="${INSTALL_PREFIX}/etc/xrdp"
    mkdir -p "$cfg_dir"

    # Copy our pre-built configs
    cp "$SCRIPT_DIR/config/xrdp.ini"  "$cfg_dir/xrdp.ini"
    cp "$SCRIPT_DIR/config/sesman.ini" "$cfg_dir/sesman.ini"
    cp "$SCRIPT_DIR/config/xrdp_keyboard.ini" "$cfg_dir/xrdp_keyboard.ini"

    # Generate TLS certificate for encrypted RDP
    info "Generating TLS certificate..."
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/C=US/ST=Local/L=Local/O=MacRDP/CN=macos-rdp" \
        -keyout "${cfg_dir}/key.pem" \
        -out  "${cfg_dir}/cert.pem" 2>&1 | tee -a "$LOG"

    chmod 600 "${cfg_dir}/key.pem"

    mkdir -p "${INSTALL_PREFIX}/var/run"
    mkdir -p "${INSTALL_PREFIX}/var/log"
}

install_launchd() {
    info "Installing launchd service..."

    cp "$SCRIPT_DIR/launchd/com.macrdp.xrdp.plist" \
        /Library/LaunchDaemons/com.macrdp.xrdp.plist

    chmod 644 /Library/LaunchDaemons/com.macrdp.xrdp.plist
    chown root:wheel /Library/LaunchDaemons/com.macrdp.xrdp.plist

    launchctl load -w /Library/LaunchDaemons/com.macrdp.xrdp.plist
    info "xrdp service installed and started"
}

open_firewall() {
    info "Opening firewall for RDP (port 3389)..."
    # macOS Application Firewall — allow xrdp binary
    /usr/libexec/ApplicationFirewall/socketfilterfw \
        --add "${INSTALL_PREFIX}/sbin/xrdp" \
        --unblock "${INSTALL_PREFIX}/sbin/xrdp" 2>/dev/null || true

    # If Little Snitch / other firewall present, user must add rule manually
    warn "If you use a third-party firewall (Little Snitch, etc.), allow TCP port 3389 inbound."
}

print_summary() {
    local ip
    ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "<your-mac-ip>")
    echo ""
    echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GRN}  Mac RDP Server is running!${NC}"
    echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  From Windows, open Remote Desktop Connection and enter:"
    echo ""
    echo -e "    Computer:  ${YLW}${ip}${NC}"
    echo ""
    echo "  At the login screen, enter the remote desktop password you chose."
    echo "  (Change it any time:  sudo ./rdpctl.sh setpassword)"
    echo ""
    echo "  Logs:    ${INSTALL_PREFIX}/var/log/xrdp.log"
    echo "  Config:  ${INSTALL_PREFIX}/etc/xrdp/xrdp.ini"
    echo "  Stop:    sudo launchctl unload /Library/LaunchDaemons/com.macrdp.xrdp.plist"
    echo "  Start:   sudo launchctl load -w /Library/LaunchDaemons/com.macrdp.xrdp.plist"
    echo "  Remove:  sudo bash ${SCRIPT_DIR}/uninstall.sh"
    echo ""
}

main() {
    banner
    check_root
    exec > >(tee -a "$LOG") 2>&1
    check_deps
    enable_screen_sharing
    build_xrdp
    configure_xrdp
    install_launchd
    open_firewall
    print_summary
}

main "$@"
