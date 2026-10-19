#!/bin/sh
# Copyright 2026 The dahliaOS Authors
# SPDX-License-Identifier: Apache-2.0
#
# Builds everything a Pangolin session needs: river (with Pangolin's
# extensions, when zig is available), the shell, the dahliaOS apps and the
# settings daemon.
#
# usage: tool/build.sh [--debug] [--clean]
#   --clean  drop previous build output first (needed after building on another
#            system or container: CMake caches that system's library paths)
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ "$(id -u)" = 0 ]; then
    echo "build.sh: run this as your normal user; only tool/install.sh needs root" >&2
    exit 1
fi
MODE=release
CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --debug) MODE=debug ;;
        --clean) CLEAN=1 ;;
        *) echo "build.sh: unknown option $arg" >&2; exit 2 ;;
    esac
done

FLUTTER=${FLUTTER:-}
if [ -z "$FLUTTER" ]; then
    if command -v flutter >/dev/null 2>&1; then
        FLUTTER=$(command -v flutter)
    else
        FLUTTER="$HOME/.local/flutter/bin/flutter"
    fi
fi
[ -x "$FLUTTER" ] || { echo "build.sh: flutter not found (set FLUTTER=/path/to/flutter)" >&2; exit 1; }
DART="$(dirname "$FLUTTER")/dart"

# Flutter's name for this machine's architecture (its build directory).
case "$(uname -m)" in
    x86_64|amd64) FLUTTER_ARCH=x64 ;;
    aarch64|arm64) FLUTTER_ARCH=arm64 ;;
    *) echo "build.sh: Flutter doesn't build for $(uname -m) (x86_64 and aarch64 only)" >&2; exit 1 ;;
esac

ZIG=${ZIG:-$(command -v zig || true)}

# Development files every part needs (pkg-config names), checked before
# anything is touched: one clear message rather than a failure halfway.
need="gtk+-3.0 gtk-layer-shell-0 epoxy wayland-client"
[ -n "$ZIG" ] && need="$need libevdev libinput wayland-server wayland-protocols wlroots-0.20 xkbcommon pixman-1"
if ! command -v pkg-config >/dev/null 2>&1; then
    echo "build.sh: pkg-config is missing (install pkgconf)" >&2
    exit 1
fi
missing=""
for pc in $need; do
    pkg-config --exists "$pc" 2>/dev/null || missing="$missing $pc"
done
if [ -n "$missing" ]; then
    echo "build.sh: missing development files:$missing" >&2
    # Package names per distribution family.
    distro=$( (. /etc/os-release 2>/dev/null; echo "${ID:-} ${ID_LIKE:-}") )
    case " $distro " in
        *" fedora "*|*" rhel "*|*" centos "*|*" suse "*|*" opensuse "*)
            cmd="sudo dnf install"
            case " $distro " in *suse*) cmd="sudo zypper install" ;; esac
            pkgs=""
            for pc in $missing; do pkgs="$pkgs 'pkgconfig($pc)'"; done
            echo "Install them with:  $cmd$pkgs" >&2 ;;
        *" debian "*|*" ubuntu "*)
            pkgs=""
            for pc in $missing; do
                case "$pc" in
                    gtk+-3.0) p=libgtk-3-dev ;; gtk-layer-shell-0) p=libgtk-layer-shell-dev ;;
                    epoxy) p=libepoxy-dev ;; wayland-client|wayland-server) p=libwayland-dev ;;
                    wlroots-0.20) p=libwlroots-0.20-dev ;;
                    xkbcommon) p=libxkbcommon-dev ;; pixman-1) p=libpixman-1-dev ;;
                    wayland-protocols) p=wayland-protocols ;; *) p="$pc-dev" ;;
                esac
                pkgs="$pkgs $p"
            done
            echo "Install them with:  sudo apt install$pkgs" >&2 ;;
        *" arch "*)
            pkgs=""
            for pc in $missing; do
                case "$pc" in
                    gtk+-3.0) p=gtk3 ;; gtk-layer-shell-0) p=gtk-layer-shell ;; epoxy) p=libepoxy ;;
                    wayland-client|wayland-server) p=wayland ;;
                    wlroots-0.20) p=wlroots0.20 ;; xkbcommon) p=libxkbcommon ;; pixman-1) p=pixman ;;
                    *) p="$pc" ;;
                esac
                pkgs="$pkgs $p"
            done
            echo "Install them with:  sudo pacman -S$pkgs" >&2 ;;
        *" alpine "*)
            pkgs=""
            for pc in $missing; do
                case "$pc" in
                    gtk+-3.0) p=gtk+3.0-dev ;; gtk-layer-shell-0) p=gtk-layer-shell-dev ;;
                    epoxy) p=libepoxy-dev ;; wayland-client|wayland-server) p=wayland-dev ;;
                    wlroots-0.20) p=wlroots-dev ;;
                    xkbcommon) p=libxkbcommon-dev ;; pixman-1) p=pixman-dev ;;
                    wayland-protocols) p=wayland-protocols ;; *) p="$pc-dev" ;;
                esac
                pkgs="$pkgs $p"
            done
            echo "Install them with:  sudo apk add$pkgs" >&2 ;;
    esac
    if [ -e /run/.toolboxenv ] || [ -e /run/.containerenv ]; then
        : # Already in a container.
    elif command -v toolbox >/dev/null 2>&1 || command -v distrobox >/dev/null 2>&1; then
        echo "Or run tool/build.sh inside the container you develop in (toolbox, distrobox)." >&2
    fi
    exit 1
fi

# A CMake cache made on another system (the host vs. a container) records
# tool and library paths that don't exist here: drop it so CMake reconfigures.
drop_foreign_cmake_cache() {
    cache="$1/build/linux/$FLUTTER_ARCH/$MODE/CMakeCache.txt"
    [ -f "$cache" ] || return 0
    sed -n 's/^[A-Za-z0-9_+.-]*:FILEPATH=//p' "$cache" | while read -r path; do
        case "$path" in /*) [ -e "$path" ] || { echo stale; break; } ;; esac
    done | grep -q stale || return 0
    echo "==> $(basename "$1"): build tree was configured on another system, reconfiguring"
    rm -rf "${1:?}/build/linux/$FLUTTER_ARCH/$MODE"
}
drop_foreign_cmake_cache "$ROOT"
drop_foreign_cmake_cache "$ROOT/apps"

if [ "$CLEAN" = 1 ]; then
    echo "==> Cleaning previous builds"
    (cd "$ROOT" && "$FLUTTER" clean)
    (cd "$ROOT/apps" && "$FLUTTER" clean)
    rm -rf "$ROOT/session/dsettingsd/build" "$ROOT/session/displays/build" \
        "$ROOT/session/portal/build"
fi

if [ -n "$ZIG" ]; then
    echo "==> river"
    RIVER_MODE=ReleaseSafe
    [ "$MODE" = debug ] && RIVER_MODE=Debug
    (cd "$ROOT/river-main/river" && "$ZIG" build "-Doptimize=$RIVER_MODE" -Dxwayland)
else
    echo "==> river: zig not found, keeping the river already built (if any)"
fi

# Pangolin's build of Flutter's Linux embedder (tool/build_engine.sh): frames
# at the display's refresh rate instead of 60 Hz, and only what changed sent
# to the compositor. Release builds of the same engine version only.
ENGINE_LIB="$ROOT/third_party/flutter_engine/$FLUTTER_ARCH/libflutter_linux_gtk.so"
SDK_ENGINE=$(cat "$(dirname "$(readlink -f "$FLUTTER")")/internal/engine.version" 2>/dev/null || true)
use_patched_engine() {
    bundle="$1/build/linux/$FLUTTER_ARCH/$MODE/bundle/lib"
    if [ "$MODE" != release ] || [ ! -f "$ENGINE_LIB" ]; then
        return
    fi
    if [ "$SDK_ENGINE" != "$(cat "$ROOT/third_party/flutter_engine/engine.version")" ]; then
        echo "build.sh: third_party/flutter_engine is for another engine version than the SDK's ($SDK_ENGINE): keeping the stock embedder (rebuild it with tool/build_engine.sh)" >&2
        return
    fi
    cp "$ENGINE_LIB" "$bundle/libflutter_linux_gtk.so"
    echo "    using Pangolin's Flutter embedder"
}

echo "==> Pangolin shell ($MODE)"
(cd "$ROOT" && "$FLUTTER" pub get && "$FLUTTER" build linux "--$MODE")
use_patched_engine "$ROOT"

echo "==> dahliaOS apps ($MODE)"
(cd "$ROOT/apps" && "$FLUTTER" pub get && "$FLUTTER" build linux "--$MODE")
use_patched_engine "$ROOT/apps"

echo "==> dsettingsd"
(cd "$ROOT/session/dsettingsd" && "$DART" pub get &&
    mkdir -p build && "$DART" compile exe bin/dsettingsd.dart -o build/dsettingsd)

echo "==> cursor theme"
"$DART" run "$ROOT/tool/cursors/generate.dart" "$ROOT/session/cursors/build"

echo "==> pangolin-displays"
(cd "$ROOT/session/displays" && "$DART" pub get &&
    mkdir -p build && "$DART" compile exe bin/pangolin_displays.dart -o build/pangolin-displays)

echo "==> pangolin-portal"
(cd "$ROOT/session/portal" && "$DART" pub get &&
    mkdir -p build && "$DART" compile exe bin/pangolin_portal.dart -o build/pangolin-portal)

FLAG=""
[ "$MODE" = debug ] && FLAG=" --debug"
echo "Done. Install with: tool/install.sh$FLAG"
