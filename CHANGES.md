# Changes

## 2026-11-15
- **Smooth scrolling** (`patches/01-smooth-scroll.patch`): xrdp ignored the
  wheel rotation amount (one VNC click per event). The delta is now
  accumulated: 1 notch = 5 lines by default, and touchpads scroll in
  proportion. Tune with `sudo ./rdpctl.sh scroll <percent> [invert|normal]`.
- **Faster default**: `max_bpp` 32 → 16, which halves every frame through the
  raw-only VNC bridge. `sudo ./rdpctl.sh quality best` restores 32-bit.
- **Security**: the login screen now asks for the Screen Sharing password
  instead of storing it in `xrdp.ini` (xrdp's VNC module ignores usernames).
- Removed the unused pf port redirect; xrdp binds 3389 directly.
- Audio channel off (the VNC bridge carries no audio).
- `update.sh`: rebuild and reinstall over an existing install.
