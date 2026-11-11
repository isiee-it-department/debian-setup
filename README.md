# debian-setup

One command to install a developer workstation on **Debian 13 (trixie) + KDE Plasma**.

```bash
curl -fsSL https://raw.githubusercontent.com/isiee-it-department/debian-setup/main/install-debian.sh | bash
```

Run it as a normal user with `sudo` rights. It is safe to run again: anything already installed is skipped.

## What it installs

| Source | Packages |
|---|---|
| Debian (main, contrib, non-free) | zsh, jq, htop, btop, ffmpeg, imagemagick, unrar, sassc, gdebi, build-essential, default-jdk, python3-pip/venv, samba-common-bin, slirp4netns, uidmap, flatpak, exfatprogs, systemd-zram-generator, firefox-esr, nala, obs-studio, fcitx5 + fcitx5-unikey |
| Vendor apt repos | Docker CE (+ rootless extras), GitHub CLI, Terraform, Google Cloud CLI, cloudflared, Cloudflare WARP, VS Code, Claude Desktop |
| `.deb` | Google Chrome, AWS Session Manager plugin, RustDesk |
| Flathub | Bitwarden, Slack, Discord, draw.io |
| User tools (`~/.local`) | fnm + Node 22, pnpm (standalone), Bun, uv, graphify, rustup, AWS CLI v2, Bitwarden CLI, Claude Code, rtk, multica |

It also enables zram swap, adds you to the `docker` group, and writes `~/.config/shell/debian-setup.sh` (PATH for the user tools), sourced from `.bashrc` and `.zshrc`.

## Options

| Variable | Effect |
|---|---|
| `FORCE=1` | Run on something other than Debian 13 |
| `SKIP_DESKTOP=1` | Skip GUI apps (servers, containers) |

```bash
curl -fsSL .../install-debian.sh | SKIP_DESKTOP=1 bash
```

## After it finishes

1. Log out and back in (docker group, PATH).
2. Vietnamese typing on KDE Wayland: System Settings > Keyboard > Virtual Keyboard > **Fcitx 5**, then add Unikey under Input Method.
