#!/bin/sh
# Copyright 2026 The dahliaOS Authors
# SPDX-License-Identifier: Apache-2.0
#
# Makes the source tarball, dist/pangolin-desktop-VERSION.tar.xz: everything
# needed to build Pangolin (river's Zig dependencies included), without build
# outputs and caches. VERSION comes from pubspec.yaml unless set.
#
# usage: tool/dist.sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${VERSION:-$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' "$ROOT/pubspec.yaml")}
NAME="pangolin-desktop-$VERSION"
OUT="$ROOT/dist"
mkdir -p "$OUT"

# Directory names that are build outputs or caches wherever they are, then
# build directories at fixed places (river's dependencies have source
# directories called build).
tar --create --file - -C "$ROOT" \
    --sort=name --owner=0 --group=0 --numeric-owner \
    --transform "s,^\.,$NAME," \
    --no-anchored \
    --exclude=.dart_tool --exclude=.zig-cache --exclude=ephemeral \
    --exclude=.idea --exclude=.git --exclude='.flutter-plugins*' \
    --anchored \
    --exclude=./dist --exclude=./build --exclude=./apps/build \
    --exclude=./river-main/river/zig-out \
    --exclude=./session/dsettingsd/build --exclude=./session/displays/build \
    --exclude=./session/cursors/build \
    . | xz -T0 -6 > "$OUT/$NAME.tar.xz.tmp"
mv "$OUT/$NAME.tar.xz.tmp" "$OUT/$NAME.tar.xz"
echo "$OUT/$NAME.tar.xz"
