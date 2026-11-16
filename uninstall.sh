#!/usr/bin/env bash
# Mac RDP Server — uninstaller

set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GRN}[+]${NC} $*"; }
warn() { echo -e "${RED}[-]${NC} $*"; }

[[ $EUID -ne 0 ]] && { echo "Run with sudo."; exit 1; }

info "Stopping services..."
launchctl unload /Library/LaunchDaemons/com.macrdp.xrdp.plist 2>/dev/null || true
launchctl unload /Library/LaunchDaemons/com.macrdp.pf.plist   2>/dev/null || true

info "Removing launchd plists..."
rm -f /Library/LaunchDaemons/com.macrdp.xrdp.plist
rm -f /Library/LaunchDaemons/com.macrdp.pf.plist

info "Removing pf rules..."
rm -f /etc/pf.anchors/com.macrdp
# Remove Mac RDP lines from pf.conf
sed -i '' '/# Mac RDP Server/,+2d' /etc/pf.conf 2>/dev/null || true
pfctl -f /etc/pf.conf 2>/dev/null || true

info "Removing xrdp installation..."
rm -rf /opt/mac-rdp

info "Done. macOS Screen Sharing remains enabled — disable it in System Settings → General → Sharing if desired."
