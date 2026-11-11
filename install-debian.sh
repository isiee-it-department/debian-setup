#!/usr/bin/env bash
# install-debian.sh - cai dat goi cho Debian 13 (trixie) + KDE Plasma.
#
#   curl -fsSL https://raw.githubusercontent.com/isiee-it-department/debian-setup/main/install-debian.sh | bash
#
# Chay bang user thuong (khong phai root); script tu goi sudo khi can.
# Chay lai nhieu lan van an toan: goi/repo nao da co thi bo qua.
# Bien moi truong:
#   FORCE=1         chay ca khi khong phai Debian 13
#   SKIP_DESKTOP=1  bo qua app giao dien (Chrome, VS Code, Flatpak, RustDesk...)

set -euo pipefail

# ---------------------------------------------------------------- helpers
c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_dim=$'\e[2m'; c_off=$'\e[0m'
step() { printf '\n%s==> %s%s\n' "$c_ok" "$*" "$c_off"; }
info() { printf '%s    %s%s\n' "$c_dim" "$*" "$c_off"; }
warn() { printf '%s[!] %s%s\n' "$c_warn" "$*" "$c_off"; WARNINGS+=("$*"); }
die()  { printf '%s[x] %s%s\n' "$c_err" "$*" "$c_off" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
WARNINGS=()

KEYRINGS=/etc/apt/keyrings
SOURCES=/etc/apt/sources.list.d
ARCH=amd64
CODENAME=trixie
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export DEBIAN_FRONTEND=noninteractive
APT=(sudo -E apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# Tai key ve $KEYRINGS/<name>.asc hoac .gpg (tuy key dang text hay binary). In ra duong dan.
add_key() { # name url
  local name=$1 url=$2 f="$TMP/$1.key" dest
  for ext in asc gpg; do [ -s "$KEYRINGS/$name.$ext" ] && { echo "$KEYRINGS/$name.$ext"; return; }; done
  curl -fsSL "$url" -o "$f" || die "Khong tai duoc key $name tu $url"
  if head -c 40 "$f" | grep -q -- '-----BEGIN PGP'; then dest="$KEYRINGS/$name.asc"; else dest="$KEYRINGS/$name.gpg"; fi
  sudo install -m 0644 "$f" "$dest"
  echo "$dest"
}

# Ghi file deb822 vao sources.list.d (ghi de, nen chay lai van dung).
add_source() { # name uri suite components keyfile
  sudo tee "$SOURCES/$1.sources" >/dev/null <<EOF
Types: deb
URIs: $2
Suites: $3
Components: $4
Architectures: $ARCH
Signed-By: $5
EOF
}

# Repo nao chua co ban trixie thi lui ve bookworm.
pick_suite() { # base_uri
  local s
  for s in "$CODENAME" bookworm; do
    if curl -fsI "$1/dists/$s/InRelease" >/dev/null 2>&1 || curl -fsI "$1/dists/$s/Release" >/dev/null 2>&1; then
      echo "$s"; return
    fi
  done
  echo "$CODENAME"
}

# Chi cai nhung goi co trong repo; goi thieu thi canh bao thay vi lam hong ca lenh.
apt_install() {
  local ok=() p
  for p in "$@"; do
    if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed'; then continue; fi
    if apt-cache show "$p" >/dev/null 2>&1; then ok+=("$p"); else warn "Khong tim thay goi apt: $p"; fi
  done
  [ ${#ok[@]} -eq 0 ] && { info "apt: tat ca da duoc cai"; return; }
  "${APT[@]}" install "${ok[@]}"
}

# Cai file .deb tu URL (bo qua neu goi da co).
deb_install() { # pkgname url
  if dpkg -s "$1" >/dev/null 2>&1; then info "$1 da duoc cai"; return; fi
  curl -fsSL "$2" -o "$TMP/$1.deb" || { warn "Khong tai duoc $1 tu $2"; return; }
  "${APT[@]}" install "$TMP/$1.deb" || warn "Cai $1 that bai"
}

# URL cua asset moi nhat tren GitHub release khop regex.
gh_asset() { # owner/repo regex
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4 | grep -E "$2" | head -1
}

# Tai tarball tu GitHub release, lay file binary ten $3 dua vao ~/.local/bin.
gh_binary() { # owner/repo regex binary
  local url d="$TMP/$3"
  url=$(gh_asset "$1" "$2") || true
  [ -n "$url" ] || { warn "Khong tim thay ban phat hanh cua $1"; return; }
  mkdir -p "$d" && curl -fsSL "$url" | tar xz -C "$d" || { warn "Tai $1 that bai"; return; }
  local bin; bin=$(find "$d" -type f -name "$3" | head -1)
  [ -n "$bin" ] || { warn "Khong thay file $3 trong $url"; return; }
  install -m 0755 "$bin" "$HOME/.local/bin/$3"
  info "$3 -> ~/.local/bin ($(basename "$url"))"
}

# ---------------------------------------------------------------- checks
preflight() {
  [ "$(id -u)" -ne 0 ] || die "Hay chay bang user thuong, khong dung root/sudo."
  [ "$(dpkg --print-architecture)" = "$ARCH" ] || die "Script chi ho tro amd64."
  . /etc/os-release
  if [ "${ID:-}" != debian ] || [ "${VERSION_CODENAME:-}" != "$CODENAME" ]; then
    [ "${FORCE:-0}" = 1 ] || die "Can Debian 13 (trixie), dang la ${PRETTY_NAME:-?}. Dat FORCE=1 de chay van."
    warn "Khong phai Debian 13 (${PRETTY_NAME:-?}), van chay vi FORCE=1"
  fi
  have sudo || die "Chua co sudo. Chay: su -c 'apt install sudo && usermod -aG sudo $USER' roi dang nhap lai."
  sudo -v || die "Can quyen sudo."
  # giu sudo song trong suot qua trinh cai
  while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
  mkdir -p "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.local/share/pnpm:$HOME/.local/share/fnm:$PATH"
}

# ---------------------------------------------------------------- apt base
enable_nonfree() {
  step "Bat contrib / non-free / non-free-firmware"
  local f=$SOURCES/debian.sources
  if [ -f "$f" ]; then
    sudo sed -i -E 's/^Components:.*/Components: main contrib non-free non-free-firmware/' "$f"
  fi
  if [ -f /etc/apt/sources.list ] && grep -qE '^deb .*debian' /etc/apt/sources.list; then
    sudo sed -i -E '/^deb(-src)? .*debian/ s/ main( contrib| non-free| non-free-firmware)*\s*$/ main contrib non-free non-free-firmware/' /etc/apt/sources.list
  fi
  sudo apt-get update -q
  apt_install ca-certificates curl wget gnupg git unzip
  sudo install -d -m 0755 "$KEYRINGS"
}

base_packages() {
  step "Goi tu repo Debian"
  apt_install \
    zsh jq htop btop ffmpeg imagemagick unrar sassc gdebi build-essential pkg-config \
    default-jdk python3-pip python3-venv python3-netifaces \
    samba-common-bin slirp4netns uidmap dbus-user-session \
    flatpak ostree appstream-util exfatprogs systemd-zram-generator \
    firefox-esr nala
  if [ "${SKIP_DESKTOP:-0}" != 1 ]; then
    apt_install obs-studio fcitx5 fcitx5-unikey kde-config-fcitx5 plasma-discover-backend-flatpak
  fi
}

# ---------------------------------------------------------------- vendor repos
vendor_repos() {
  step "Them repo cua nha cung cap"
  local k s

  k=$(add_key docker https://download.docker.com/linux/debian/gpg)
  add_source docker https://download.docker.com/linux/debian "$CODENAME" stable "$k"

  k=$(add_key github-cli https://cli.github.com/packages/githubcli-archive-keyring.gpg)
  add_source github-cli https://cli.github.com/packages stable main "$k"

  k=$(add_key hashicorp https://apt.releases.hashicorp.com/gpg)
  s=$(pick_suite https://apt.releases.hashicorp.com)
  add_source hashicorp https://apt.releases.hashicorp.com "$s" main "$k"

  k=$(add_key google-cloud https://packages.cloud.google.com/apt/doc/apt-key.gpg)
  add_source google-cloud-sdk https://packages.cloud.google.com/apt cloud-sdk main "$k"

  k=$(add_key cloudflared https://pkg.cloudflare.com/cloudflare-main.gpg)
  add_source cloudflared https://pkg.cloudflare.com/cloudflared any main "$k"

  k=$(add_key cloudflare-warp https://pkg.cloudflareclient.com/pubkey.gpg)
  s=$(pick_suite https://pkg.cloudflareclient.com)
  add_source cloudflare-client https://pkg.cloudflareclient.com "$s" main "$k"

  if [ "${SKIP_DESKTOP:-0}" != 1 ]; then
    k=$(add_key microsoft https://packages.microsoft.com/keys/microsoft.asc)
    add_source vscode https://packages.microsoft.com/repos/code stable main "$k"
    # khong de goi code tu them repo trung lap
    echo "code code/add-microsoft-repo boolean false" | sudo debconf-set-selections

    # Claude Desktop: Anthropic chua cong bo URL tai key, nen key duoc nhung ngay ben duoi.
    if [ ! -s "$KEYRINGS/claude-desktop.asc" ]; then
      claude_desktop_key | sudo tee "$KEYRINGS/claude-desktop.asc" >/dev/null
      gpg --show-keys --with-colons "$KEYRINGS/claude-desktop.asc" 2>/dev/null \
        | grep -q '^fpr:::::::::31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE:' \
        || die "Fingerprint key Claude Desktop khong khop"
    fi
    add_source claude-desktop https://downloads.claude.ai/claude-desktop/apt/stable stable main "$KEYRINGS/claude-desktop.asc"
  fi

  sudo apt-get update -q
}

vendor_packages() {
  step "Goi tu repo nha cung cap"
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    docker-ce-rootless-extras gh terraform google-cloud-cli cloudflared cloudflare-warp
  [ "${SKIP_DESKTOP:-0}" = 1 ] || apt_install code claude-desktop

  if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    info "Da them $USER vao nhom docker (co hieu luc sau khi dang nhap lai)"
  fi
}

# ---------------------------------------------------------------- .deb + flatpak
desktop_apps() {
  [ "${SKIP_DESKTOP:-0}" = 1 ] && return
  step "App cai bang .deb"
  deb_install google-chrome-stable https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  deb_install session-manager-plugin https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb
  local u; u=$(gh_asset rustdesk/rustdesk 'rustdesk-unattended-wayland-[0-9.]+-x86_64\.deb$') || true
  if [ -n "$u" ]; then deb_install rustdesk-unattended-wayland "$u"; else warn "Khong tim thay ban .deb cua RustDesk"; fi

  step "App Flatpak (Flathub)"
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  local app
  for app in com.bitwarden.desktop com.slack.Slack com.discordapp.Discord com.jgraph.drawio.desktop; do
    flatpak info "$app" >/dev/null 2>&1 && { info "$app da duoc cai"; continue; }
    sudo flatpak install -y --noninteractive flathub "$app" || warn "Cai Flatpak that bai: $app"
  done
}

# ---------------------------------------------------------------- user tools
user_tools() {
  step "Cong cu trong thu muc user"

  if ! have fnm; then
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$HOME/.local/share/fnm" --skip-shell
  fi
  eval "$(fnm env --shell bash)"
  fnm list | grep -q 'v22\.' || fnm install 22
  fnm default 22

  have pnpm || curl -fsSL https://get.pnpm.io/install.sh | env SHELL=/bin/bash PNPM_HOME="$HOME/.local/share/pnpm" sh -
  have bun  || curl -fsSL https://bun.sh/install | bash
  have uv   || curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
  uv tool list 2>/dev/null | grep -q '^graphifyy' || uv tool install graphifyy || warn "Cai graphify that bai"
  have rustup || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

  if ! have aws; then
    curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "$TMP/awscli.zip"
    unzip -q "$TMP/awscli.zip" -d "$TMP"
    "$TMP/aws/install" -i "$HOME/.local/aws-cli" -b "$HOME/.local/bin" --update
  fi

  # Bitwarden CLI cai tu npm va chay bang Node he thong voi --no-network-family-autoselection:
  # ban binary dong goi san bo qua NODE_OPTIONS, va bao ETIMEDOUT khi ket noi toi Bitwarden
  # cham hon 250ms tren mang khong co IPv6.
  if [ ! -f "$HOME/.local/share/bw-cli/node_modules/@bitwarden/cli/build/bw.js" ]; then
    npm install --silent --prefix "$HOME/.local/share/bw-cli" @bitwarden/cli >/dev/null || warn "Cai Bitwarden CLI that bai"
  fi
  cat > "$HOME/.local/bin/bw" <<'EOF'
#!/bin/sh
NODE="$HOME/.local/share/fnm/aliases/default/bin/node"; [ -x "$NODE" ] || NODE=node
exec "$NODE" --no-network-family-autoselection "$HOME/.local/share/bw-cli/node_modules/@bitwarden/cli/build/bw.js" "$@"
EOF
  chmod 0755 "$HOME/.local/bin/bw"

  have claude  || curl -fsSL https://claude.ai/install.sh | bash
  have rtk     || gh_binary rtk-ai/rtk 'rtk-oss-x86_64-unknown-linux-musl\.tar\.gz$' rtk
  have multica || gh_binary multica-ai/multica '/multica_linux_amd64\.tar\.gz$' multica
}

# ---------------------------------------------------------------- system config
system_config() {
  step "Cau hinh he thong"
  if [ ! -f /etc/systemd/zram-generator.conf ]; then
    sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF
    info "Da bat zram (co hieu luc sau khi khoi dong lai)"
  fi

  # PATH cho cac cong cu cai trong thu muc user; nap tu .bashrc va .zshrc
  mkdir -p "$HOME/.config/shell"
  cat > "$HOME/.config/shell/debian-setup.sh" <<'EOF'
# Tao boi install-debian.sh
export PNPM_HOME="$HOME/.local/share/pnpm"
for d in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.bun/bin" "$PNPM_HOME" "$HOME/.local/share/fnm"; do
  case ":$PATH:" in *":$d:"*) ;; *) [ -d "$d" ] && PATH="$d:$PATH" ;; esac
done
export PATH
if command -v fnm >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then eval "$(fnm env --use-on-cd --shell zsh)"; else eval "$(fnm env --use-on-cd --shell bash)"; fi
fi
EOF
  local line='[ -f "$HOME/.config/shell/debian-setup.sh" ] && . "$HOME/.config/shell/debian-setup.sh"' rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    touch "$rc"; grep -qF '.config/shell/debian-setup.sh' "$rc" || printf '\n%s\n' "$line" >> "$rc"
  done
}

# ---------------------------------------------------------------- summary
summary() {
  step "Xong"
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    printf '%sCanh bao:%s\n' "$c_warn" "$c_off"; printf '  - %s\n' "${WARNINGS[@]}"
  fi
  cat <<'EOF'

Viec tiep theo:
  1. Dang xuat roi dang nhap lai (de nhom docker va PATH co hieu luc).
  2. Dang nhap GitHub:   gh auth login --git-protocol https --web
  3. Mo khoa Bitwarden:  export BW_SESSION="$(bw login --raw)"   # da dang nhap roi thi: bw unlock --raw
  4. Chay repo cai dat ca nhan cua ban (neu co).

Go tieng Viet tren KDE Wayland: System Settings > Keyboard > Virtual Keyboard > chon "Fcitx 5",
roi them Unikey trong System Settings > Input Method.
EOF
}

claude_desktop_key() {
  cat <<'KEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGnK73ABEACnbytJXkjweYrwIr0aLEFRlH+C0nF44KxFc7gQmJ6PjSPMGZAD
dxZcaixU7zZl8WxEpVO0wLmIH8cf2zGOdyuZg1Yaugk1vHb2b8WBhAGCQJdPgB8W
XquedepEYtk56uP/gCoTjJDUZluEGBHnlnuujSJ4orxEdhSykEoAUfJZGEILPpMd
bphFt/Sn+Eb/TxM5jpKPdwnv8AShNF/1mZU1fWTQq9tRKJUakZj04gdaDFElQXak
CtTij+GT6yoYCARSHwGO+PC/Pr6q4tc+D7LRjxSBvUWDoFSmlqb/PJ1hj9D/7I2O
e4XXniAPWMR56KvxHlzOzrNQdJujbJdSkCwh1ZijkSd3y8ayW5WYUTGdRab99NUw
agzlabe/VVF6kzJ0Scn5q3PihB2Y9Bwo0CKnkYk7a7KT77EWv0Kkq+VHmOtqX3a2
hhX+b6a6ve9rzJ1qZYGj+obv/C3Sx1LzUjAfqVy7RJDf2uAoP5t2g8u/TkSpUxhM
VEjZBkSxYZhMyzQM6t8IgkUfnSrIPTHixbDWARZ4beMOBjxyPZK1nP7OOrNR3TkK
JtwLMQAabURCDnL0PjS0iwBTU4jtumBD1XSULyWuoTvMljrpQr1nV1oDyOt0OLqa
KA2McWtd9PdXhC8y2EIg7TmrTlJLfHYbdmkiCYj4J49Q8HWkN/6WE+RTUwARAQAB
tD5BbnRocm9waWMgQ2xhdWRlIENvZGUgUmVsZWFzZSBTaWduaW5nIDxzZWN1cml0
eUBhbnRocm9waWMuY29tPokCUQQTAQoAOxYhBDHd3iTd+rZ59C170rqpKf8afsrO
BQJpyu9wAhsPBQsJCAcCAiICBhUKCQgLAgQWAgMBAh4HAheAAAoJELqpKf8afsrO
l5IP/2I8X1dFy5xYczWB/coIxGjuzS/V6ByZGZZEJsbr04pmuHiFUykJqPGWGQ6q
U0YF5iEwvEkaagS5m7DzhSEf3FM3Cgafax/6d70tar9Vr1D+w6uPfxetu7u/WYJp
aolIsdh5fTrBh9zSM1Njl8FM8wG8CwZQjS33Oa7d8cwRkgdUWbt6LXgz+cTQNuBn
BgW6Ks7oZFI25dfu0ojDR+aDFJg4+4wZoyDLPvJz1SIrJ5WFGs67zsx9SfS3yZnf
XKmBe+f0dUy+GJ2nFZrXFf99+c0dPEHYO8DCeAHZizjkFrdYtUHdDU0YDYEGkLJa
bE+pgcpkHf5EvsZzHsyDbl95W/eh7pcXMbwkN+W4CBYUE9X4uHhqzWaC5yAVRWUA
1BJ9V4LjZfHPLEJt0I3TxzXiEg9/BVeaTYq9RjaxIFo9Nfk158HqJY6SA5jslBlx
Gv/No8u+xVcze2UJyGVfEIUfm92+0UAIkny3+5cuVV0ICzJxXlXj0CnLM9Lt50wE
p3suVwuBEviCbZ08eAH1Ht8gbBdSsiOkIU8CX3v/scwHHx5q0+NBL6xLrQObg13a
tRXBlKObfElkPN3lTUbUnJOW4U8uSjH8VRP+AujKWMDFe7x0zCs+iYY1mTOvbrTS
9n3CmZUmbynZ+E/QWNENpW/pDNZdWFy43PASmML5FHu4m9Sn
=oqMI
-----END PGP PUBLIC KEY BLOCK-----
KEY
}

main() {
  preflight
  enable_nonfree
  base_packages
  vendor_repos
  vendor_packages
  desktop_apps
  user_tools
  system_config
  summary
}

main "$@"
