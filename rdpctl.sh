#!/usr/bin/env bash
# rdpctl — Mac RDP Server control tool
# Usage: rdpctl {status|start|stop|restart|logs|setpassword|quality|scroll|ip}

set -euo pipefail

INSTALL_PREFIX="/opt/mac-rdp"
XRDP_PLIST="/Library/LaunchDaemons/com.macrdp.xrdp.plist"
LOG_DIR="${INSTALL_PREFIX}/var/log"

GRN='\033[0;32m'; RED='\033[0;31m'; YLW='\033[1;33m'; BLU='\033[0;34m'; NC='\033[0m'

cmd="${1:-status}"

get_ip() {
    ipconfig getifaddr en0 2>/dev/null \
    || ipconfig getifaddr en1 2>/dev/null \
    || ipconfig getifaddr en2 2>/dev/null \
    || echo "unknown"
}

xrdp_running() {
    launchctl list com.macrdp.xrdp &>/dev/null && \
    launchctl list com.macrdp.xrdp | grep -q '"PID"'
}

case "$cmd" in
status)
    echo ""
    if xrdp_running; then
        PID=$(launchctl list com.macrdp.xrdp | grep '"PID"' | awk '{print $3}' | tr -d ',')
        echo -e "  xrdp:     ${GRN}● running${NC}  (PID $PID)"
    else
        echo -e "  xrdp:     ${RED}○ stopped${NC}"
    fi

    if launchctl list com.apple.screensharing &>/dev/null 2>&1; then
        echo -e "  VNC:      ${GRN}● Screen Sharing enabled${NC}"
    else
        echo -e "  VNC:      ${YLW}○ Screen Sharing off${NC}  (run: sudo rdpctl setscreensharing)"
    fi

    IP=$(get_ip)
    echo ""
    echo -e "  ${BLU}Connect from Windows:${NC}  mstsc.exe → ${YLW}${IP}${NC}"
    echo ""
    ;;

start)
    [[ $EUID -ne 0 ]] && exec sudo "$0" "$@"
    echo "Starting Mac RDP Server..."
    launchctl load -w "$XRDP_PLIST" || true
    sleep 1
    "$0" status
    ;;

stop)
    [[ $EUID -ne 0 ]] && exec sudo "$0" "$@"
    echo "Stopping Mac RDP Server..."
    launchctl unload "$XRDP_PLIST" 2>/dev/null || true
    echo "Stopped."
    ;;

restart)
    [[ $EUID -ne 0 ]] && exec sudo "$0" "$@"
    "$0" stop
    sleep 1
    "$0" start
    ;;

logs)
    LINES="${2:-50}"
    echo -e "${BLU}=== xrdp log (last $LINES lines) ===${NC}"
    tail -n "$LINES" "${LOG_DIR}/xrdp.log" 2>/dev/null || \
    tail -n "$LINES" "${LOG_DIR}/xrdp-stderr.log" 2>/dev/null || \
    echo "No logs found at ${LOG_DIR}"
    ;;

setpassword)
    # Set the Screen Sharing (VNC) password — the one typed at the RDP login screen.
    # Legacy VNC auth only uses the first 8 characters.
    [[ $EUID -ne 0 ]] && exec sudo "$0" "$@"
    read -rsp "New remote desktop password (max 8 chars): " VNC_PW
    echo ""
    # Hash the password using Apple's kickstart tool
    /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
        -configure -clientopts -setvnclegacy -vnclegacy yes \
        -clientopts -setvncpw -vncpw "$VNC_PW" \
        -restart -agent 2>/dev/null || true
    echo "Password updated."
    ;;

setscreensharing)
    [[ $EUID -ne 0 ]] && exec sudo "$0" "$@"
    echo "Enabling macOS Screen Sharing..."
    launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
    echo "Done."
    ;;

quality)
    # fast = 16-bit colour (much snappier), best = 32-bit (accurate colour, slower)
    [[ $EUID -ne 0 ]] && exec sudo "$0" "$@"
    INI="${INSTALL_PREFIX}/etc/xrdp/xrdp.ini"
    case "${2:-}" in
        fast) BPP=16 ;;
        best) BPP=32 ;;
        *) echo "Usage: rdpctl quality fast|best   (current: $(grep '^max_bpp=' "$INI"))"; exit 1 ;;
    esac
    sed -i '' "s/^max_bpp=.*/max_bpp=${BPP}/" "$INI"
    echo "Colour depth set to ${BPP}-bit. Restarting..."
    "$0" restart
    echo "Reconnect from Windows to apply."
    ;;

scroll)
    # rdpctl scroll <percent> [invert|normal]   100 = 1 line per wheel notch
    [[ $EUID -ne 0 ]] && exec sudo "$0" "$@"
    PB=/usr/libexec/PlistBuddy
    SPEED="${2:-}"
    if [[ ! "$SPEED" =~ ^[0-9]+$ ]] || [[ "$SPEED" -lt 1 ]]; then
        echo "Usage: rdpctl scroll <percent> [invert|normal]"
        echo "  current speed:  $($PB -c 'Print :EnvironmentVariables:MACRDP_SCROLL_SPEED' "$XRDP_PLIST" 2>/dev/null || echo 500)%"
        echo "  current invert: $($PB -c 'Print :EnvironmentVariables:MACRDP_SCROLL_INVERT' "$XRDP_PLIST" 2>/dev/null || echo 0)"
        exit 1
    fi
    $PB -c "Add :EnvironmentVariables dict" "$XRDP_PLIST" 2>/dev/null || true
    $PB -c "Delete :EnvironmentVariables:MACRDP_SCROLL_SPEED" "$XRDP_PLIST" 2>/dev/null || true
    $PB -c "Add :EnvironmentVariables:MACRDP_SCROLL_SPEED string $SPEED" "$XRDP_PLIST"
    case "${3:-}" in
        invert) INV=1 ;; normal) INV=0 ;; *) INV="" ;;
    esac
    if [[ -n "$INV" ]]; then
        $PB -c "Delete :EnvironmentVariables:MACRDP_SCROLL_INVERT" "$XRDP_PLIST" 2>/dev/null || true
        $PB -c "Add :EnvironmentVariables:MACRDP_SCROLL_INVERT string $INV" "$XRDP_PLIST"
    fi
    echo "Scroll speed set to ${SPEED}%${INV:+ (invert=$INV)}. Restarting..."
    "$0" restart
    echo "Reconnect from Windows to apply."
    ;;

ip)
    echo "Mac IP: $(get_ip)"
    echo "Connect Windows users to: $(get_ip):3389"
    ;;

*)
    echo "Usage: rdpctl {status|start|stop|restart|logs [N]|setpassword|setscreensharing|quality fast|best|scroll <pct> [invert|normal]|ip}"
    exit 1
    ;;
esac
