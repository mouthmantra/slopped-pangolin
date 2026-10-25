#!/bin/sh
# Copyright 2026 The dahliaOS Authors
# SPDX-License-Identifier: Apache-2.0
#
# Installs a built Pangolin session (see tool/build.sh) into a prefix.
#
# usage: tool/install.sh [--prefix DIR] [--destdir DIR] [--debug] [--system-session] [--greeter] [--uninstall]
#   --prefix DIR       install location (default: ~/.local, or /usr/local as root)
#   --destdir DIR      stage the files under DIR (DIR/PREFIX/...) for a package
#                      (RPM, deb...); system changes (users, PAM, greetd) are
#                      left to the package, see packaging/
#   --debug            install the debug builds instead of the release builds
#   --system-session   also list Pangolin in display managers such as GDM
#                      (writes /usr/share/wayland-sessions, needs root)
#   --greeter          set up Pangolin's login screen for greetd (needs root
#                      and a system prefix such as /usr/local; implies
#                      --system-session). Switching display managers is left
#                      to you, see the message at the end.
#   --uninstall        remove a previous installation from the prefix
#
# Run it on the machine that will run Pangolin: inside a toolbox or distrobox
# container /usr belongs to the container, so system-wide installs and
# display manager entries must be made from a host terminal.
set -eu
# Installed files must be readable by every user, even under a strict umask.
umask 022

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Under sudo $HOME is root's: a system-wide install is what's meant.
if [ "$(id -u)" = 0 ]; then PREFIX=/usr/local; else PREFIX="$HOME/.local"; fi
MODE=release
UNINSTALL=0
SYSTEM_SESSION=0
GREETER=0
DESTDIR=
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX=$2; shift 2 ;;
        --prefix=*) PREFIX=${1#--prefix=}; shift ;;
        --destdir) DESTDIR=$2; shift 2 ;;
        --destdir=*) DESTDIR=${1#--destdir=}; shift ;;
        --debug) MODE=debug; shift ;;
        --system-session) SYSTEM_SESSION=1; shift ;;
        --greeter) GREETER=1; SYSTEM_SESSION=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        *) echo "install.sh: unknown option $1" >&2; exit 2 ;;
    esac
done
case "$PREFIX" in /*) ;; *) PREFIX="$(pwd)/$PREFIX" ;; esac
if [ -n "$DESTDIR" ]; then
    case "$DESTDIR" in /*) ;; *) DESTDIR="$(pwd)/$DESTDIR" ;; esac
    # Staging for a package: nothing outside DESTDIR is touched.
    SYSTEM_SESSION=0
    GREETER=0
fi
# Where files are written; installed files refer to PREFIX.
P="$DESTDIR$PREFIX"

# Installs under a home directory can't be seen by other users (GDM's greeter
# runs as its own user): their session entry must not use TryExec.
in_home=0
case "$PREFIX" in /home/*|/root/*|"$HOME"/*) in_home=1 ;; esac

in_container=0
[ -e /run/.toolboxenv ] || [ -e /run/.containerenv ] && in_container=1
system_prefix=0
case "$PREFIX" in /usr|/usr/*|/opt|/opt/*) system_prefix=1 ;; esac
if [ -z "$DESTDIR" ] && [ "$in_container" = 1 ] && { [ "$system_prefix" = 1 ] || [ "$SYSTEM_SESSION" = 1 ]; }; then
    echo "install.sh: this is a container (toolbox/distrobox): its /usr isn't the host's," >&2
    echo "so GDM would never see this installation. Run from a host terminal instead:" >&2
    echo "  sudo $0${*:+ $*} --prefix $PREFIX$( [ "$SYSTEM_SESSION" = 1 ] && echo " --system-session")" >&2
    exit 1
fi

# The greeter runs as its own user: it can't use an installation inside a
# home directory.
if [ "$GREETER" = 1 ] && [ "$in_home" = 1 ]; then
    echo "install.sh: --greeter needs a system-wide prefix, e.g." >&2
    echo "  sudo $0 --prefix /usr/local --greeter" >&2
    exit 1
fi

# Fail early, with a hint, instead of halfway through copying.
check_dir=$P
while [ ! -d "$check_dir" ]; do check_dir=$(dirname "$check_dir"); done
if [ ! -w "$check_dir" ]; then
    echo "install.sh: $PREFIX isn't writable; run: sudo $0 --prefix $PREFIX" >&2
    exit 1
fi

APPS="activity_monitor calculator clock disks files gallery logs settings store terminal text_editor welcome"
SHARE="$P/share"

uninstall() {
    rm -rf "$P/lib/pangolin" "$P/lib/dahlia-apps" "$P/libexec/pangolin"
    rm -f "$P/bin/pangolin" "$P/bin/dahlia_apps" "$P/bin/pangolin-session" \
        "$P/bin/pangolin-greeter"
    # The river earlier versions of this script installed in bin.
    if [ -e "$P/lib/pangolin-river" ]; then
        rm -rf "$P/bin/river" "$P/lib/pangolin-river"
    fi
    rm -f "$SHARE/dbus-1/services/io.dahlia.DSettings.service"
    rm -f "$SHARE/wayland-sessions/pangolin.desktop"
    rm -f "$SHARE/systemd/user/pangolin-session.target"
    rm -f "$SHARE/xdg-desktop-portal/pangolin-portals.conf"
    rm -f "$SHARE/xdg-desktop-portal/portals/pangolin.portal"
    rm -f "$SHARE/dbus-1/services/org.freedesktop.impl.portal.desktop.pangolin.service"
    rm -rf "$SHARE/icons/Pangolin" "$SHARE/licenses/pangolin" "$SHARE/pangolin" \
        "$SHARE/fonts/pangolin-inter"
    if [ "$SYSTEM_SESSION" = 1 ] || [ "$(id -u)" = 0 ]; then
        rm -f /usr/share/wayland-sessions/pangolin.desktop
    fi
    # Only this installation's (a package may own one for /usr).
    if [ -z "$DESTDIR" ] && [ "$(id -u)" = 0 ] &&
        grep -qs "$PREFIX/libexec/pangolin/" /usr/share/polkit-1/actions/io.dahliaos.logs.policy; then
        rm -f /usr/share/polkit-1/actions/io.dahliaos.logs.policy
    fi
    if [ "$UNINSTALL" = 1 ]; then
        # The dahliaOS app style: its cleanup entry (only this
        # installation's), and for the user running this, the libadwaita
        # line and the generated themes.
        for entry in "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/pangolin-gtk-style-off.desktop" \
            /etc/xdg/autostart/pangolin-gtk-style-off.desktop; do
            grep -qs "$PREFIX/libexec/pangolin/" "$entry" && rm -f "$entry"
        done
        css="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/gtk.css"
        if grep -qs 'pangolin-dahlia\.css' "$css"; then
            sed -i '/pangolin-dahlia\.css/d' "$css"
            grep -q '[^[:space:]]' "$css" || rm -f "$css"
        fi
        rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/pangolin-dahlia.css"
        for theme in "${XDG_DATA_HOME:-$HOME/.local/share}"/themes/dahliaOS-*; do
            [ -e "$theme/.pangolin-generated" ] && rm -rf "$theme"
        done
    fi
    if [ "$UNINSTALL" = 1 ] && [ "$(id -u)" = 0 ]; then
        rm -f /etc/systemd/system/plymouth-quit.service.d/pangolin-greeter.conf
        rmdir /etc/systemd/system/plymouth-quit.service.d 2>/dev/null || true
        rm -f /etc/logrotate.d/pangolin
    fi
    for app in $APPS; do
        rm -f "$SHARE/applications/io.dahliaos.$app.desktop"
        rm -f "$SHARE"/icons/hicolor/*/apps/"io.dahliaos.$app.png"
    done
}

if [ "$UNINSTALL" = 1 ]; then
    uninstall
    echo "Removed Pangolin from $PREFIX"
    exit 0
fi

RIVER="$ROOT/river-main/river/zig-out/bin/river"
# Flutter builds into a directory named after the architecture.
case "$(uname -m)" in
    aarch64|arm64) FLUTTER_ARCH=arm64 ;;
    *) FLUTTER_ARCH=x64 ;;
esac
SHELL_BUNDLE="$ROOT/build/linux/$FLUTTER_ARCH/$MODE/bundle"
APPS_BUNDLE="$ROOT/apps/build/linux/$FLUTTER_ARCH/$MODE/bundle"
DSETTINGSD="$ROOT/session/dsettingsd/build/dsettingsd"
DISPLAYS="$ROOT/session/displays/build/pangolin-displays"
PORTAL="$ROOT/session/portal/build/pangolin-portal"
for f in "$SHELL_BUNDLE/pangolin" "$APPS_BUNDLE/dahlia_apps" "$DSETTINGSD" "$DISPLAYS" "$PORTAL"; do
    [ -x "$f" ] || { echo "install.sh: $f is missing, run tool/build.sh first" >&2; exit 1; }
done

subst() {
    sed -e "s|@PREFIX@|$PREFIX|g" -e "s|@BINDIR@|$PREFIX/bin|g" "$1" > "$2"
}

uninstall
mkdir -p "$P/bin" "$P/lib" "$P/libexec/pangolin" \
    "$SHARE/applications" "$SHARE/dbus-1/services" "$SHARE/wayland-sessions"

# Flutter bundles find their data next to the real executable, so the bundles
# stay whole under lib/ and bin/ gets symlinks.
cp -R "$SHELL_BUNDLE" "$P/lib/pangolin"
cp -R "$APPS_BUNDLE" "$P/lib/dahlia-apps"
ln -s ../lib/pangolin/pangolin "$P/bin/pangolin"
ln -s ../lib/dahlia-apps/dahlia_apps "$P/bin/dahlia_apps"
cp "$DSETTINGSD" "$P/libexec/pangolin/dsettingsd"
cp "$DISPLAYS" "$P/libexec/pangolin/pangolin-displays"
cp "$PORTAL" "$P/libexec/pangolin/pangolin-portal"
# Pangolin needs its own river (window effects, blur, gestures extensions):
# in libexec, apart from a river the distribution may have.
if [ -x "$RIVER" ]; then
    cp "$RIVER" "$P/libexec/pangolin/river"
    chmod 755 "$P/libexec/pangolin/river"
elif [ -n "$DESTDIR" ]; then
    # A package has no river to fall back on (1.1.0-17 shipped without it
    # when zig wasn't found, and sessions didn't start).
    echo "install.sh: $RIVER is missing (tool/build.sh needs zig 0.16 on PATH or in ZIG); not staging a package without river" >&2
    exit 1
fi
# The bundles keep their build-time modes: open them up the same way.
chmod -R a+rX "$P/lib/pangolin" "$P/lib/dahlia-apps" "$P/libexec/pangolin"

subst "$ROOT/session/bin/pangolin-session.in" "$P/bin/pangolin-session"
subst "$ROOT/session/libexec/pangolin-river-init.in" "$P/libexec/pangolin/pangolin-river-init"
subst "$ROOT/session/bin/pangolin-greeter.in" "$P/bin/pangolin-greeter"
subst "$ROOT/session/libexec/pangolin-greeter-init.in" "$P/libexec/pangolin/pangolin-greeter-init"
subst "$ROOT/session/libexec/pangolin-read-logs.in" "$P/libexec/pangolin/pangolin-read-logs"
subst "$ROOT/session/libexec/pangolin-gtk-style-off.in" "$P/libexec/pangolin/pangolin-gtk-style-off"
chmod 755 "$P/bin/pangolin-greeter" "$P/libexec/pangolin/pangolin-greeter-init"
chmod 755 "$P/bin/pangolin-session" "$P/libexec/pangolin/pangolin-river-init" \
    "$P/libexec/pangolin/dsettingsd" "$P/libexec/pangolin/pangolin-displays" \
    "$P/libexec/pangolin/pangolin-portal" "$P/libexec/pangolin/pangolin-read-logs" \
    "$P/libexec/pangolin/pangolin-gtk-style-off"

for app in $APPS; do
    subst "$ROOT/session/applications/io.dahliaos.$app.desktop.in" \
        "$SHARE/applications/io.dahliaos.$app.desktop"
done
subst "$ROOT/session/dbus/io.dahlia.DSettings.service.in" \
    "$SHARE/dbus-1/services/io.dahlia.DSettings.service"
subst "$ROOT/session/dbus/org.freedesktop.impl.portal.desktop.pangolin.service.in" \
    "$SHARE/dbus-1/services/org.freedesktop.impl.portal.desktop.pangolin.service"
subst "$ROOT/session/wayland-sessions/pangolin.desktop.in" \
    "$SHARE/wayland-sessions/pangolin.desktop"
mkdir -p "$SHARE/systemd/user" "$SHARE/xdg-desktop-portal"
cp "$ROOT/session/systemd/pangolin-session.target" "$SHARE/systemd/user/"
cp "$ROOT/session/xdg-desktop-portal/pangolin-portals.conf" "$SHARE/xdg-desktop-portal/"
mkdir -p "$SHARE/xdg-desktop-portal/portals"
cp "$ROOT/session/xdg-desktop-portal/pangolin.portal" "$SHARE/xdg-desktop-portal/portals/"
mkdir -p "$SHARE/pangolin/greeter-services"
subst "$ROOT/session/dbus/pangolin-greeter-bus.conf.in" "$SHARE/pangolin/pangolin-greeter-bus.conf"
cp "$SHARE/dbus-1/services/io.dahlia.DSettings.service" "$SHARE/pangolin/greeter-services/"
# xdg-desktop-portal-wlr only reads its configuration from the user's config
# directory or /etc/xdg: add Pangolin's without replacing one the user has.
if [ -n "$DESTDIR" ]; then
    XDPW_CONFIG="$DESTDIR/etc/xdg/xdg-desktop-portal-wlr"
elif [ "$(id -u)" = 0 ]; then
    XDPW_CONFIG=/etc/xdg/xdg-desktop-portal-wlr
else
    XDPW_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal-wlr"
fi
if [ ! -e "$XDPW_CONFIG/Pangolin" ]; then
    mkdir -p "$XDPW_CONFIG"
    cp "$ROOT/session/xdg-desktop-portal-wlr/Pangolin" "$XDPW_CONFIG/Pangolin"
fi
if [ -z "$DESTDIR" ] && command -v systemctl >/dev/null 2>&1 && [ "$(id -u)" != 0 ]; then
    systemctl --user daemon-reload 2>/dev/null || true
fi
# Other desktops take Pangolin's libadwaita style out when they start
# (pangolin-gtk-style-off): autostart is only read from /etc/xdg and the
# user's config directory.
if [ -n "$DESTDIR" ]; then
    AUTOSTART="$DESTDIR/etc/xdg/autostart"
elif [ "$(id -u)" = 0 ]; then
    AUTOSTART=/etc/xdg/autostart
else
    AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
fi
mkdir -p "$AUTOSTART"
subst "$ROOT/session/autostart/pangolin-gtk-style-off.desktop.in" "$AUTOSTART/pangolin-gtk-style-off.desktop"
chmod 644 "$AUTOSTART/pangolin-gtk-style-off.desktop"
# Logs' authorization for reading system logs: polkit only reads actions
# from /usr/share, so system installs and packages (per-user installs ask
# each time through pkexec's own action).
if [ -n "$DESTDIR" ] || [ "$(id -u)" = 0 ]; then
    mkdir -p "$DESTDIR/usr/share/polkit-1/actions"
    subst "$ROOT/session/polkit/io.dahliaos.logs.policy.in" \
        "$DESTDIR/usr/share/polkit-1/actions/io.dahliaos.logs.policy"
    chmod 644 "$DESTDIR/usr/share/polkit-1/actions/io.dahliaos.logs.policy"
fi
if [ "$in_home" = 1 ]; then
    sed -i '/^TryExec=/d' "$SHARE/wayland-sessions/pangolin.desktop"
fi
if [ "$SYSTEM_SESSION" = 1 ] || { [ -z "$DESTDIR" ] && [ "$(id -u)" = 0 ] && [ "$PREFIX" != /usr ]; }; then
    if [ "$(id -u)" != 0 ]; then
        echo "install.sh: --system-session needs root: sudo $0 --prefix $PREFIX --system-session" >&2
        exit 1
    fi
    mkdir -p /usr/share/wayland-sessions
    cp "$SHARE/wayland-sessions/pangolin.desktop" /usr/share/wayland-sessions/pangolin.desktop
    chmod 644 /usr/share/wayland-sessions/pangolin.desktop
    # The lock screen's own PAM service (it falls back to "login" without):
    # passwords only, like GDM's gdm-password. The stack console logins use
    # can start with the fingerprint reader (Fedora's "with-fingerprint"),
    # which holds the password check for up to 30 seconds.
    if [ -d /etc/pam.d ] && { [ ! -e /etc/pam.d/pangolin ] ||
        grep -q "Pangolin's lock screen" /etc/pam.d/pangolin; }; then
        pam_stack=login
        for candidate in password-auth common-auth system-auth system-login; do
            if [ -e "/etc/pam.d/$candidate" ]; then pam_stack=$candidate; break; fi
        done
        {
            echo "# PAM configuration of Pangolin's lock screen: checks the password"
            echo "# (written by tool/install.sh from /etc/pam.d/$pam_stack)."
            case "$pam_stack" in
                common-auth)
                    # Debian splits the stacks by type.
                    echo "auth     include  common-auth"
                    echo "account  include  common-account"
                    ;;
                *)
                    echo "auth     include  $pam_stack"
                    echo "account  include  $pam_stack"
                    ;;
            esac
        } > /etc/pam.d/pangolin
        chmod 644 /etc/pam.d/pangolin
    fi
    # The session's log, writable by the user installing it (other users'
    # sessions log to ~/.local/state/pangolin/Pangolin.log).
    log_owner=${SUDO_USER:-}
    if [ -n "$log_owner" ] && [ "$log_owner" != root ] && [ -d /var/log ]; then
        touch /var/log/Pangolin.log
        chown "$log_owner:$(id -gn "$log_owner")" /var/log/Pangolin.log
        chmod 644 /var/log/Pangolin.log
    fi
    # Where users share their wallpaper and display setup with the login
    # screen: anyone may add files, nobody may touch another user's (sticky,
    # like /tmp).
    mkdir -p /var/lib/pangolin/users
    chmod 755 /var/lib/pangolin
    chmod 1777 /var/lib/pangolin/users
    if [ -d /etc/logrotate.d ]; then
        cat > /etc/logrotate.d/pangolin <<'LOGROTATE'
# Pangolin's session and login screen logs (tool/install.sh).
/var/log/Pangolin.log /var/log/PangolinGreeter.log {
    weekly
    rotate 2
    maxsize 8M
    missingok
    notifempty
    compress
    copytruncate
}
LOGROTATE
        chmod 644 /etc/logrotate.d/pangolin
    fi
fi

# greetd with Pangolin's login screen.
if [ "$GREETER" = 1 ]; then
    # The login screen runs as a user of its own, as GDM's does (gdm).
    greeter_user=pangolin-greeter
    nologin=/usr/sbin/nologin
    [ -x "$nologin" ] || nologin=/sbin/nologin
    [ -x "$nologin" ] || nologin=/bin/false
    if ! getent passwd "$greeter_user" >/dev/null 2>&1; then
        if command -v useradd >/dev/null 2>&1; then
            useradd --system --home-dir /var/lib/pangolin-greeter --no-create-home \
                --shell "$nologin" --comment "Pangolin login screen" "$greeter_user" ||
                greeter_user=""
        elif command -v adduser >/dev/null 2>&1; then
            # busybox (Alpine)
            adduser -S -D -H -h /var/lib/pangolin-greeter -s "$nologin" \
                -g "Pangolin login screen" "$greeter_user" || greeter_user=""
        else
            greeter_user=""
        fi
    fi
    if [ -n "$greeter_user" ]; then
        # Screens and input devices: logind hands them to the login screen's
        # session; with seatd (no logind) the seat group grants them.
        for group in video render input seat; do
            getent group "$group" >/dev/null 2>&1 || continue
            if command -v usermod >/dev/null 2>&1; then
                usermod -a -G "$group" "$greeter_user" 2>/dev/null || true
            elif command -v addgroup >/dev/null 2>&1; then
                addgroup "$greeter_user" "$group" 2>/dev/null || true
            fi
        done
    fi
    if ! command -v greetd >/dev/null 2>&1 && [ ! -x /usr/sbin/greetd ]; then
        echo "install.sh: greetd isn't installed (e.g. sudo dnf install greetd), skipping the greeter" >&2
    elif [ -z "$greeter_user" ]; then
        echo "install.sh: couldn't create the pangolin-greeter user, skipping the greeter" >&2
    else
        mkdir -p /var/lib/pangolin-greeter
        chown -R "$greeter_user:$(id -gn "$greeter_user")" /var/lib/pangolin-greeter
        chmod 700 /var/lib/pangolin-greeter
        # SELinux (Fedora): greetd runs the login screen confined (xdm_t),
        # which may only watch and replace files in a display manager's own
        # state (xdm_var_lib_t, like /var/lib/gdm): the settings daemon and
        # the cached splash image need that.
        if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
            if command -v semanage >/dev/null 2>&1; then
                semanage fcontext -a -t xdm_var_lib_t '/var/lib/pangolin-greeter(/.*)?' 2>/dev/null ||
                    semanage fcontext -m -t xdm_var_lib_t '/var/lib/pangolin-greeter(/.*)?' 2>/dev/null || true
                restorecon -R /var/lib/pangolin-greeter 2>/dev/null || true
            else
                chcon -R -t xdm_var_lib_t /var/lib/pangolin-greeter 2>/dev/null || true
            fi
            restorecon -R /var/lib/pangolin 2>/dev/null || true
        fi
        touch /var/log/PangolinGreeter.log
        chown "$greeter_user:$(id -gn "$greeter_user")" /var/log/PangolinGreeter.log
        chmod 644 /var/log/PangolinGreeter.log
        # Keep the boot splash on screen until the login screen replaces it
        # instead of showing the text console in between (as GDM does).
        if [ -d /run/systemd/system ] && command -v plymouth >/dev/null 2>&1; then
            mkdir -p /etc/systemd/system/plymouth-quit.service.d
            cat > /etc/systemd/system/plymouth-quit.service.d/pangolin-greeter.conf <<PLYMOUTH
# Written by Pangolin's tool/install.sh --greeter: the boot splash stays on
# screen until the login screen takes over, no text console in between.
[Service]
ExecStart=
ExecStart=-$(command -v plymouth) quit --retain-splash
PLYMOUTH
            systemctl daemon-reload 2>/dev/null || true
        fi
        mkdir -p /etc/greetd
        vt=1
        if [ -f /etc/greetd/config.toml ]; then
            vt=$(sed -n 's/^vt *= *"\{0,1\}\([0-9a-z]*\)"\{0,1\}.*/\1/p' /etc/greetd/config.toml | head -n 1)
            [ -n "$vt" ] || vt=1
            # vt = "next" and the like stay strings.
            case "$vt" in *[!0-9]*) vt="\"$vt\"" ;; esac
            [ -e /etc/greetd/config.toml.before-pangolin ] ||
                cp /etc/greetd/config.toml /etc/greetd/config.toml.before-pangolin
        fi
        cat > /etc/greetd/config.toml <<GREETD
# Written by Pangolin's tool/install.sh --greeter (the previous file, if any,
# is /etc/greetd/config.toml.before-pangolin).
[terminal]
vt = $vt

[default_session]
command = "$PREFIX/bin/pangolin-greeter"
user = "$greeter_user"
GREETD
        GREETER_READY=1
    fi
fi

for size_dir in "$ROOT"/session/icons/hicolor/*; do
    size=${size_dir##*/}
    mkdir -p "$SHARE/icons/hicolor/$size/apps"
    cp "$size_dir"/apps/*.png "$SHARE/icons/hicolor/$size/apps/"
done
# Pointer theme (generated by tool/build.sh).
if [ -d "$ROOT/session/cursors/build/Pangolin" ]; then
    rm -rf "$SHARE/icons/Pangolin"
    mkdir -p "$SHARE/icons"
    cp -R "$ROOT/session/cursors/build/Pangolin" "$SHARE/icons/Pangolin"
    chmod -R a+rX "$SHARE/icons/Pangolin"
fi
# Inter, Pangolin's interface font, for GTK and other apps too (the shell
# and dahliaOS apps carry their own copy): the dahliaOS app style uses it.
mkdir -p "$SHARE/fonts/pangolin-inter"
cp "$ROOT"/packages/zenit_ui/lib/src/fonts/Inter-*.ttf "$SHARE/fonts/pangolin-inter/"
chmod a+r "$SHARE"/fonts/pangolin-inter/*.ttf
if [ -z "$DESTDIR" ] && command -v fc-cache >/dev/null 2>&1; then
    fc-cache "$SHARE/fonts/pangolin-inter" >/dev/null 2>&1 || true
fi
# License texts, where distributions keep them: the binaries carry code
# under several licenses (see docs/DISTRIBUTING.md).
mkdir -p "$SHARE/licenses/pangolin"
cp "$ROOT/LICENSE" "$SHARE/licenses/pangolin/Apache-2.0.txt"
cp "$ROOT"/river-main/river/LICENSES/*.txt "$SHARE/licenses/pangolin/"
cp "$ROOT/packages/zenit_ui/lib/src/fonts/OFL.txt" "$SHARE/licenses/pangolin/OFL-1.1-Inter.txt"
cp "$ROOT/tool/cursors/adwaita/README.md" "$SHARE/licenses/pangolin/Adwaita-cursors.md"
chmod -R a+rX "$SHARE/licenses/pangolin"
touch "$SHARE/icons/hicolor"
if [ -n "$DESTDIR" ]; then
    echo "Staged Pangolin for $PREFIX in $DESTDIR"
    exit 0
fi
# A stale icon-theme.cache left by another app would hide these icons from
# toolkits that trust it: rebuild it.
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -f -t "$SHARE/icons/hicolor" 2>/dev/null || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q "$SHARE/applications" || true
fi

echo "Installed Pangolin to $PREFIX"

# An older copy in the installing user's home (tool/install.sh without
# sudo) comes first in the search paths: its desktop entries would start its
# old apps and its cursor theme would replace this one. Remove it.
if [ "$in_home" = 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [ -n "$user_home" ] && [ -x "$user_home/.local/lib/pangolin/pangolin" ] &&
        [ "$user_home/.local" != "$PREFIX" ]; then
        if [ "${PANGOLIN_KEEP_USER_INSTALL:-}" = 1 ]; then
            echo "Note: $user_home/.local has another copy of Pangolin, which hides this one" >&2
        else
            echo "Removing the older copy of Pangolin in $user_home/.local (it would hide this one;"
            echo "  PANGOLIN_KEEP_USER_INSTALL=1 keeps it)"
            sudo -u "$SUDO_USER" "$0" --prefix "$user_home/.local" --uninstall >/dev/null ||
                echo "install.sh: couldn't remove it, run: $0 --prefix ~/.local --uninstall" >&2
        fi
    fi
fi
# Screen sharing and recording need the wlroots portal backend.
xdpw_found=0
for d in /usr/libexec /usr/lib /usr/lib64 /usr/local/libexec /usr/lib/xdg-desktop-portal-wlr \
    /run/host/usr/libexec /run/host/usr/lib; do
    [ -x "$d/xdg-desktop-portal-wlr" ] && xdpw_found=1
done
command -v xdg-desktop-portal-wlr >/dev/null 2>&1 && xdpw_found=1
if [ "$xdpw_found" = 0 ]; then
    echo "Note: screen recording and sharing (OBS, browsers) need xdg-desktop-portal-wlr:"
    echo "  install it with your package manager, e.g. sudo dnf install xdg-desktop-portal-wlr"
    echo "  (apt install xdg-desktop-portal-wlr, pacman -S xdg-desktop-portal-wlr, apk add xdg-desktop-portal-wlr)"
fi
[ -x "$PREFIX/libexec/pangolin/river" ] ||
    echo "Note: river isn't built yet: run tool/build.sh (needs zig) and install again."
if [ "${GREETER_READY:-0}" = 1 ]; then
    echo "Pangolin's login screen is set up for greetd. To switch to it (from a host terminal):"
    echo "  sudo systemctl disable gdm && sudo systemctl enable greetd   # then reboot"
    echo "To go back: sudo systemctl disable greetd && sudo systemctl enable gdm"
fi
if [ -e /usr/share/wayland-sessions/pangolin.desktop ] && [ "$in_container" = 0 ]; then
    echo "Pangolin is listed in the display manager's session menu."
else
    echo "Start it with $PREFIX/bin/pangolin-session (or --nested inside another desktop)."
    echo "To list it in GDM, from a host terminal: sudo $0 --prefix $PREFIX --system-session"
fi
