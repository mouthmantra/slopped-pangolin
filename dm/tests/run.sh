#!/bin/sh
# Copyright 2026 The dahliaOS Authors
# SPDX-License-Identifier: Apache-2.0
#
# pangolin-dm end to end, as any user (no root, no VT): the daemon in test
# mode with PAM services from a scratch folder (a test module that asks for
# a password), a scripted greeter (greeter.py) and a test session that
# records what it got. usage: dm/tests/run.sh [DAEMON]

set -eu
here=$(cd "$(dirname "$0")" && pwd)
cc=${CC:-cc}
t=$(mktemp -d "${TMPDIR:-/tmp}/pangolin-dm-test.XXXXXX")
# The socket's folder: a short path (socket addresses are 108 bytes).
run=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pdm.XXXXXX")
trap 'rm -rf "$t" "$run"' EXIT

daemon=${1:-}
if [ -z "$daemon" ]; then
    daemon=$t/pangolin-dm
    $cc -std=c17 -O2 -Wall -Wextra -o "$daemon" "$here"/../src/*.c -l:libpam.so.0
fi
$cc -std=c17 -O2 -Wall -Wextra -shared -fPIC -o "$t/pam_pangolin_test.so" "$here/pam_pangolin_test.c"

mkdir -p "$t/pam" "$t/data/wayland-sessions"
cat > "$t/pam/pangolin-dm" <<EOF
auth     required $t/pam_pangolin_test.so
account  required pam_permit.so
password required pam_permit.so
session  required pam_permit.so
EOF
cat > "$t/pam/pangolin-dm-greeter" <<EOF
auth     required pam_permit.so
account  required pam_permit.so
session  required pam_permit.so
EOF
cat > "$t/session.sh" <<EOF
#!/bin/sh
{ echo "args: \$*"; env | sort; } > "$t/session.out"
EOF
chmod +x "$t/session.sh"
cat > "$t/data/wayland-sessions/test.desktop" <<EOF
[Desktop Entry]
Name=Test
Exec=$t/session.sh one "two words" %U
DesktopNames=Test;Wayland;
EOF

status=0
timeout 30 "$daemon" --test --once --run-dir "$run/dm" --pam-confdir "$t/pam" \
    --sessions "$t/data" --greeter "python3 -I $here/greeter.py $t/greeter.out" \
    2> "$t/daemon.log" || status=$?

fail=0
check() {
    if grep -qx -- "$1" "$t/session.out" 2>/dev/null; then
        echo "ok   session: $1"
    else
        echo "FAIL session: $1"
        fail=1
    fi
}
cat "$t/greeter.out" 2>/dev/null || { echo "FAIL the greeter didn't run"; fail=1; }
grep -q "^failures: 0$" "$t/greeter.out" 2>/dev/null || fail=1
check "args: one two words"
check "XDG_SESSION_TYPE=wayland"
check "XDG_SESSION_CLASS=user"
check "XDG_SESSION_DESKTOP=test"
check "XDG_CURRENT_DESKTOP=Test:Wayland"
check "PANGOLIN_FROM_GREETER=1"
check "USER=$(id -un)"
if grep -q "^LD_PRELOAD=" "$t/session.out" 2>/dev/null; then
    echo "FAIL session: the greeter's LD_PRELOAD got through"
    fail=1
else
    echo "ok   session: no LD_PRELOAD from the greeter"
fi
if [ "$status" -ne 0 ]; then
    echo "FAIL daemon exited with $status"
    fail=1
fi
if [ "$fail" -ne 0 ]; then
    echo "--- daemon log"
    cat "$t/daemon.log"
    exit 1
fi
echo "pangolin-dm: all passed"
