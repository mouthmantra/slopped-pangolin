#!/bin/sh
# Copyright 2026 The dahliaOS Authors
# SPDX-License-Identifier: Apache-2.0
#
# Rebuilds third_party/flutter_engine/x64/libflutter_linux_gtk.so: Flutter's
# Linux embedder (release) with Pangolin's patch, for the engine version of
# the Flutter SDK in use. tool/build.sh puts it in the bundles in place of
# the stock one. The patch:
#   - paces frames to the fastest display (the stock engine runs at a fixed
#     60 Hz); FLUTTER_LINUX_FPS=N sets a rate, 0 or "unlimited" no limit;
#   - reports what changed in a frame (the engine diffs its layer trees,
#     shell/common/rasterizer.cc): GTK repaints only that, and the
#     compositor composites only that (Mesa reports the whole surface to it
#     otherwise, GTK 3 binding wl_compositor version 3);
#   - answers vsync on the engine's UI thread.
#
# Needs ~15 GB under ENGINE_DIR (default ~/Developer/flutter-engine), git and
# python3; takes about an hour the first time.
#
# usage: [ENGINE_DIR=...] [FLUTTER=...] tool/build_engine.sh

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENGINE_DIR=${ENGINE_DIR:-$HOME/Developer/flutter-engine}
FLUTTER=${FLUTTER:-$(command -v flutter || echo "$HOME/.local/flutter/bin/flutter")}
VERSION=$(cat "$(dirname "$(readlink -f "$FLUTTER")")/internal/engine.version")
OUT="$ROOT/third_party/flutter_engine"

mkdir -p "$ENGINE_DIR"
cd "$ENGINE_DIR"
[ -d depot_tools ] ||
    git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$ENGINE_DIR/depot_tools:$PATH" DEPOT_TOOLS_UPDATE=0
(cd depot_tools && ./ensure_bootstrap)

if [ ! -d flutter/.git ]; then
    mkdir -p flutter
    git -C flutter init -q
    git -C flutter remote add origin https://github.com/flutter/flutter.git
fi
cd flutter
git fetch --depth 1 origin "$VERSION"
git checkout -q --force FETCH_HEAD
git clean -fdq engine/src/flutter/shell/platform/linux
git apply "$OUT/pangolin-linux-embedder.patch"

# Linux desktop only.
cat > .gclient <<'EOF'
solutions = [{
  "name": ".", "url": "https://github.com/flutter/flutter.git",
  "deps_file": "DEPS", "managed": False, "safesync_url": "", "custom_deps": {},
  "custom_vars": {"download_android_deps": False, "download_fuchsia_deps": False,
                  "download_jdk": False, "download_esbuild": False},
}]
EOF
gclient sync -D --no-history

cd engine/src
./flutter/tools/gn --runtime-mode=release --no-rbe
ninja -C out/host_release flutter/shell/platform/linux:flutter_linux_gtk

mkdir -p "$OUT/x64"
cp out/host_release/libflutter_linux_gtk.so "$OUT/x64/"
strip --strip-unneeded "$OUT/x64/libflutter_linux_gtk.so"
echo "$VERSION" > "$OUT/engine.version"
echo "Built $OUT/x64/libflutter_linux_gtk.so for engine $VERSION"
