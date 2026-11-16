# Mac RDP Server

Connect to a Mac from Windows with the built-in **Remote Desktop Connection** app (`mstsc.exe`). No extra software on the Windows side.

It builds [xrdp](https://github.com/neutrinolabs/xrdp) on macOS and connects it to macOS's own Screen Sharing (VNC) service. Windows speaks RDP to xrdp, and xrdp speaks VNC to Screen Sharing on `127.0.0.1:5900`.

```
Windows mstsc ──RDP:3389──▶ xrdp (on the Mac) ──VNC:5900 (localhost)──▶ macOS Screen Sharing
```

## Features

- Works with the stock Windows Remote Desktop client
- **Smooth scrolling patch.** Stock xrdp ignores how far the wheel turns, so mouse scrolling is slow and touchpad scrolling jumps. The patch in `patches/` fixes this, and the speed is adjustable.
- A speed preset (16-bit colour) and a colour-accurate preset (32-bit)
- Clipboard sharing, TLS encryption, and auto-start at boot via launchd
- `rdpctl.sh` to check status, start/stop the server, and change scroll, quality and password settings

## Requirements

- macOS on Apple Silicon or Intel
- [Homebrew](https://brew.sh)
- Xcode Command Line Tools (the installer offers to install them)
- An administrator account

## Install

```bash
git clone https://github.com/bigtalonsbot-glitch/mac-rdp-server.git
cd mac-rdp-server
sudo bash install.sh
```

The installer:
- installs the build dependencies through Homebrew
- turns on Screen Sharing and asks you to choose a **remote desktop password**
- builds xrdp 0.9.24 with the patches applied
- generates a self-signed TLS certificate
- installs a launchd service

Then, on Windows, open **Remote Desktop Connection**, enter the Mac's IP address or `yourmac.local`, and type the password at the login screen.

## Commands

```bash
./rdpctl.sh status                  # running? Screen Sharing on? Mac IP
sudo ./rdpctl.sh restart
./rdpctl.sh logs 100
sudo ./rdpctl.sh setpassword        # change the remote desktop password
sudo ./rdpctl.sh quality fast       # 16-bit colour (default): much snappier
sudo ./rdpctl.sh quality best       # 32-bit colour: accurate, slower
sudo ./rdpctl.sh scroll 500         # lines per wheel notch x100 (500 = 5 lines)
sudo ./rdpctl.sh scroll 300 invert  # 3 lines, reversed ("natural") direction
```

After changing files in this repo (or pulling updates), run `sudo bash update.sh`. It reapplies the patches, rebuilds, reinstalls the configs and restarts, keeping your certificate.

## Making it faster

- **Lower the Mac's display resolution.** This is the biggest win: every frame passes through VNC as raw pixels, so fewer pixels means less lag.
- Leave `quality fast` on unless you need exact colour.
- In Remote Desktop Connection, go to **Show Options → Experience**, pick **LAN**, and untick font smoothing and desktop composition.
- Use a wired connection on at least one end if you can.

This bridge re-encodes every frame on the CPU, so it won't match tools that use hardware video encoding (Parsec, Moonlight/Sunshine and similar). It's for everyday desktop use, not gaming or video.

## Security: read this

- **The only password is the Screen Sharing (VNC) password.** xrdp's VNC module ignores the username, and VNC passwords only use the first 8 characters. Choose a strong one, and **never put a password in `config/xrdp.ini`**: anyone who can reach port 3389 would get your desktop.
- **Don't expose ports 3389 or 5900 to the internet.** Use it on your local network, or reach it through a VPN such as Tailscale or WireGuard.
- Screen Sharing itself also listens on port 5900 on your network. You can limit access under System Settings → General → Sharing → Screen Sharing.
- The TLS certificate is self-signed, so Windows shows a certificate warning the first time you connect.

## Uninstall

```bash
sudo bash uninstall.sh
```

This removes `/opt/mac-rdp` and the launchd service. Screen Sharing stays on; turn it off in System Settings if you like.

## License

Scripts and configs are MIT-licensed (see `LICENSE`). xrdp is licensed under Apache-2.0, so the patch in `patches/`, which modifies xrdp source, is also offered under Apache-2.0.
