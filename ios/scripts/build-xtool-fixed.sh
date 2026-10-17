#!/usr/bin/env bash
# Builds xtool from main plus the open login fixes (#348 client-info, #349 SMS fallback),
# until a release contains them. Installs to ~/.local/bin/xtool-fixed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
# libimobiledevice stack from scripts/build-limd.sh
LIMD="$HOME/.local/limd"
export PKG_CONFIG_PATH="$LIMD/lib/pkgconfig" CPATH="$LIMD/include" LIBRARY_PATH="$LIMD/lib" LD_LIBRARY_PATH="$LIMD/lib"
DIR="$HOME/build/xtool-src"
if [ ! -d "$DIR/.git" ]; then
  git clone --quiet https://github.com/xtool-org/xtool.git "$DIR"
fi
cd "$DIR"
if ! git rev-parse --verify --quiet fixed >/dev/null; then
  git -c advice.detachedHead=false checkout --quiet -B fixed origin/main
  git fetch --quiet origin pull/348/head:pr348 pull/349/head:pr349
  git -c user.name=local -c user.email=local@localhost merge --quiet --no-edit pr348 pr349
fi
git log --oneline -5
bash "$HERE/xtool-patches/apply.sh"
swift build -c release --product xtool -Xlinker -rpath -Xlinker "$LIMD/lib" 2>&1 | grep -vE "^\[" | tail -25
mkdir -p "$HOME/.local/bin"
BIN="$(swift build -c release --product xtool --show-bin-path)"
# The binary needs libXADI.so etc. from its build dir, so wrap it instead of copying.
printf '#!/bin/sh
LD_LIBRARY_PATH="%s:%s/lib" exec "%s/xtool" "$@"
' "$BIN" "$LIMD" "$BIN" > "$HOME/.local/bin/xtool-fixed"
chmod +x "$HOME/.local/bin/xtool-fixed"
"$HOME/.local/bin/xtool-fixed" --version
