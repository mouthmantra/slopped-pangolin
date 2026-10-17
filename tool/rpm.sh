#!/bin/sh
# Copyright 2026 The dahliaOS Authors
# SPDX-License-Identifier: Apache-2.0
#
# Builds Pangolin's RPMs (Fedora) from the source tarball: dist/*.rpm and
# the source RPM. Needs rpmbuild (Fedora: sudo dnf install rpm-build; in a
# Debian toolbox: sudo apt install rpm), the Flutter SDK and Zig 0.16 as
# tool/build.sh does. FLUTTER=/path/to/flutter picks the Flutter SDK.
#
# usage: [FEDORA=44] tool/rpm.sh
#   FEDORA  tag the packages for this Fedora release (default: the one
#           building, or the host's in a toolbox)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
command -v rpmbuild >/dev/null 2>&1 || {
    echo "rpm.sh: rpmbuild is missing (Fedora: sudo dnf install rpm-build; Debian: sudo apt install rpm)" >&2
    exit 1
}

TARBALL=$("$ROOT/tool/dist.sh" | tail -n 1)
TOP="$ROOT/dist/rpmbuild"
rm -rf "$TOP"
mkdir -p "$TOP/SOURCES" "$TOP/SPECS" "$TOP/BUILD" "$TOP/RPMS" "$TOP/SRPMS"
cp "$TARBALL" "$TOP/SOURCES/"
cp "$ROOT/packaging/rpm/pangolin-desktop.spec" "$TOP/SPECS/"

set -- --define "_topdir $TOP"
[ -n "${FLUTTER:-}" ] && set -- "$@" --define "flutter $FLUTTER"
if [ -z "$(rpm --eval '%{?dist}')" ]; then
    # Not on Fedora (a toolbox on a Fedora host, for instance): rpm can't
    # check the build dependencies, and the Fedora release comes from the
    # host when there is one.
    set -- "$@" --nodeps
    for release in /run/host/etc/os-release /etc/os-release; do
        [ -f "$release" ] || continue
        id=$(. "$release"; echo "${ID:-}")
        version=$(. "$release"; echo "${VERSION_ID:-}")
        if [ "$id" = fedora ] && [ -n "$version" ]; then
            FEDORA=${FEDORA:-$version}
            break
        fi
    done
fi
[ -n "${FEDORA:-}" ] && set -- "$@" --define "dist .fc$FEDORA"
rpmbuild -ba "$@" "$TOP/SPECS/pangolin-desktop.spec"
# Older builds for the same release only.
rm -f "$ROOT"/dist/*"${FEDORA:+.fc$FEDORA}".*.rpm
find "$TOP/RPMS" "$TOP/SRPMS" -name '*.rpm' -exec mv {} "$ROOT/dist/" \;
rm -rf "$TOP"
ls -1 "$TARBALL" "$ROOT"/dist/*.rpm
