#!/usr/bin/env bash
# Syncs the Windows checkout into the WSL filesystem (much faster for SwiftPM) and builds an
# unsigned EasyTrans.ipa, copied back to ./build/ for signing with Sideloadly.
# Run from Windows:  wsl -d Ubuntu-22.04 -- bash ios/scripts/build-wsl.sh
set -euo pipefail
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$HOME/build/EasyTrans"
mkdir -p "$WORK"
rsync -a --delete --exclude .build --exclude xtool --exclude build --exclude preview "$SRC/" "$WORK/"
cd "$WORK"
xtool dev build --ipa "$@"
mkdir -p "$SRC/build"
cp xtool/EasyTrans.ipa "$SRC/build/EasyTrans.ipa"
echo "IPA: $SRC/build/EasyTrans.ipa"
