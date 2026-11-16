#!/usr/bin/env bash
# Mac RDP Server — apply patches + config changes to an existing install.
# Rebuilds xrdp incrementally (no re-clone, no new TLS cert) and restarts it.
# Usage: sudo bash update.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="/opt/mac-rdp"
XRDP_SRC="$SCRIPT_DIR/build/xrdp"
CFG_DIR="${INSTALL_PREFIX}/etc/xrdp"
PLIST="/Library/LaunchDaemons/com.macrdp.xrdp.plist"
LOG="$SCRIPT_DIR/update.log"

GRN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GRN}[+]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run with sudo: sudo bash update.sh"
[[ -d "$XRDP_SRC/.git" ]] || die "No xrdp source in $XRDP_SRC — run install.sh instead."
exec > >(tee -a "$LOG") 2>&1

BREW_USER="${SUDO_USER:-$(stat -f %Su /dev/console)}"
BREW_PREFIX="$(sudo -u "$BREW_USER" brew --prefix)"
export PATH="${BREW_PREFIX}/opt/libtool/libexec/gnubin:${BREW_PREFIX}/bin:${PATH}"

cd "$XRDP_SRC"

info "Resetting tracked xrdp sources (build output is kept)..."
git checkout -- .

for p in "$SCRIPT_DIR"/patches/*.patch; do
    [[ -e "$p" ]] || continue
    info "Applying $(basename "$p")..."
    patch -p1 --forward < "$p" || die "Patch failed: $p"
done

info "Compiling..."
make -j"$(sysctl -n hw.logicalcpu)"

info "Installing to ${INSTALL_PREFIX}..."
make install

# make install drops stock configs over ours — put ours back (cert/key untouched)
info "Installing Mac RDP configs..."
cp "$SCRIPT_DIR/config/xrdp.ini"          "$CFG_DIR/xrdp.ini"
cp "$SCRIPT_DIR/config/sesman.ini"        "$CFG_DIR/sesman.ini"
cp "$SCRIPT_DIR/config/xrdp_keyboard.ini" "$CFG_DIR/xrdp_keyboard.ini"

info "Updating launchd service..."
launchctl unload "$PLIST" 2>/dev/null || true
cp "$SCRIPT_DIR/launchd/com.macrdp.xrdp.plist" "$PLIST"
chmod 644 "$PLIST"; chown root:wheel "$PLIST"
launchctl load -w "$PLIST"

info "Done. Reconnect from Windows to pick up the changes."
