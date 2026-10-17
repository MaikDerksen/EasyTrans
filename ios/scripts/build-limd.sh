#!/usr/bin/env bash
# Builds the libimobiledevice stack (same versions as xtool's Dockerfile) into ~/.local/limd.
set -euo pipefail
PREFIX="$HOME/.local/limd"
SRC="$HOME/build/limd-src"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export CPATH="$PREFIX/include"
export LIBRARY_PATH="$PREFIX/lib"
export LD_LIBRARY_PATH="$PREFIX/lib"
mkdir -p "$SRC"
build() { # name tag configure-args...
  local name=$1 tag=$2; shift 2
  if [ -f "$SRC/.$name.done" ]; then echo "== $name (cached)"; return; fi
  echo "== $name $tag"
  rm -rf "$SRC/$name"
  git clone --quiet --depth 1 --branch "$tag" "https://github.com/libimobiledevice/$name.git" "$SRC/$name"
  (cd "$SRC/$name" && ./autogen.sh --prefix="$PREFIX" "$@" >/dev/null && make -j"$(nproc)" >/dev/null && make install >/dev/null)
  touch "$SRC/.$name.done"
}
build libplist 2.6.0 --without-cython
build libimobiledevice-glue 1.3.1
build libusbmuxd 2.1.0
build libtatsu 1.0.4
build libimobiledevice master --without-cython
ls "$PREFIX/lib"/*.so
