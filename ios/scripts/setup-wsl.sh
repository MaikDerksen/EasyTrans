#!/usr/bin/env bash
# One-time toolchain setup inside WSL (Ubuntu 22.04/24.04): Swift, usbmuxd, xtool.
# Run from Windows:  wsl -d Ubuntu-22.04 -- bash ios/scripts/setup-wsl.sh
set -euo pipefail

echo "==> System packages (asks for your sudo password)"
sudo apt-get update
. /etc/os-release
GCC=11; [ "${VERSION_ID}" = "24.04" ] && GCC=13
sudo apt-get install -y \
  usbmuxd libimobiledevice-utils libfuse2 curl unzip \
  binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 "libgcc-${GCC}-dev" \
  libpython3-dev libsqlite3-0 "libstdc++-${GCC}-dev" libxml2-dev libz3-dev \
  pkg-config tzdata zlib1g-dev

echo "==> Swift toolchain via swiftly"
if ! command -v swift >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  curl -fL "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" -o "$tmp/swiftly.tar.gz"
  tar -xzf "$tmp/swiftly.tar.gz" -C "$tmp"
  "$tmp/swiftly" init --assume-yes --quiet-shell-followup
  # shellcheck disable=SC1091
  . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
fi
swift --version

echo "==> xtool"
curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" -o /tmp/xtool
chmod +x /tmp/xtool
sudo mv /tmp/xtool /usr/local/bin/xtool
xtool --help | head -3

echo "==> usbmuxd"
pgrep -x usbmuxd >/dev/null || sudo usbmuxd

cat <<'EOF'

Done. Remaining steps (they need your Apple ID, so run them yourself):
  1. Download Xcode 27 (.xip) in your browser: https://developer.apple.com/download/all/?q=Xcode
  2. In WSL run:  xtool setup
     - choose "1: Password" if you don't have a paid developer account
     - when asked, give the path to the .xip, e.g. /mnt/c/Users/<you>/Downloads/Xcode_27.0.xip
EOF
