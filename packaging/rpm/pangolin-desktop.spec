# Pangolin, the dahliaOS desktop on river, for Fedora.
#
# Built from the source tarball (tool/dist.sh) with tool/build.sh, which
# needs the Flutter SDK (not packaged in Fedora: pass its location with
# --define "flutter /path/to/flutter/bin/flutter", or have flutter on PATH),
# Zig 0.16 and network access for Dart's packages (pub get), so build it
# with rpmbuild rather than in mock. tool/rpm.sh does all of it.

%global debug_package %{nil}
# Fedora's values, also when built with plain rpm (e.g. in a toolbox).
%global _sysconfdir /etc
%global _localstatedir /var
%global _libexecdir %{_prefix}/libexec
# The Flutter bundles must not be stripped (the AOT snapshot is found by its
# symbols) and keep their own libraries.
%global __os_install_post %{nil}
%global __provides_exclude_from ^%{_prefix}/lib/(pangolin|dahlia-apps)/.*$
%global __requires_exclude ^(libflutter_linux_gtk|libapp|libhandy_flutter|lib[a-z_]+_plugin)\\.so.*$

Name:           pangolin-desktop
Version:        1.0.0
Release:        6%{?dist}
Summary:        The dahliaOS desktop (Pangolin) on the river Wayland compositor

# Pangolin and the dahliaOS apps: Apache-2.0; river: GPL-3.0-only (its
# protocols MIT); bundled Flutter and Dart packages: BSD-3-Clause and MIT;
# Inter: OFL-1.1; Adwaita's hand pointers: CC-BY-SA-3.0. See
# docs/DISTRIBUTING.md.
License:        Apache-2.0 AND GPL-3.0-only AND MIT AND BSD-3-Clause AND OFL-1.1 AND CC-BY-SA-3.0
URL:            https://github.com/dahliaOS/pangolin_desktop
Source0:        %{name}-%{version}.tar.xz

ExclusiveArch:  x86_64 aarch64

BuildRequires:  clang
BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  pkgconf-pkg-config
BuildRequires:  gtk3-devel
BuildRequires:  gtk-layer-shell-devel
BuildRequires:  libepoxy-devel
BuildRequires:  wayland-devel
BuildRequires:  wayland-protocols-devel
BuildRequires:  wlroots-devel >= 0.20
BuildRequires:  libinput-devel
BuildRequires:  libevdev-devel
BuildRequires:  libxkbcommon-devel
BuildRequires:  pixman-devel
BuildRequires:  xz

Requires:       /usr/bin/dbus-run-session
Requires:       xkeyboard-config
Requires:       hicolor-icon-theme
Recommends:     xdg-desktop-portal-wlr
Recommends:     xdg-desktop-portal-gtk
Recommends:     polkit
Recommends:     pipewire-utils
Recommends:     wireplumber
Recommends:     NetworkManager
Recommends:     wl-clipboard
Recommends:     brightnessctl
Recommends:     flatpak
Recommends:     PackageKit
Recommends:     adwaita-cursor-theme
Suggests:       nm-connection-editor
Suggests:       %{name}-greeter

%description
Pangolin is the desktop of dahliaOS: a Flutter shell (taskbar, launcher,
overview, quick settings, notifications, lock screen) running as the window
manager of river, a Wayland compositor, with the dahliaOS apps (Settings,
Files, App Store, Terminal, Text Editor, Calculator, Clock, Gallery, Activity
Monitor, Logs, Welcome).

Pangolin's river, with its extensions (window effects, blur, gestures), is
installed in %{_libexecdir}/pangolin, apart from Fedora's river.

%package greeter
Summary:        Pangolin's login screen for greetd
Requires:       %{name} = %{version}-%{release}
Requires:       greetd
Requires(pre):  shadow-utils
Requires(post): systemd
Recommends:     policycoreutils-python-utils

%description greeter
Pangolin's login screen, run by greetd as its own user (pangolin-greeter):
it shows the selected user's wallpaper and the display setup of their
desktop, keeps the boot splash up until it appears, and fades into the
desktop.

Use it instead of GDM with:
  systemctl disable gdm && systemctl enable greetd

%prep
%autosetup -n %{name}-%{version}

%build
%{?flutter:export FLUTTER=%{flutter}}
tool/build.sh

%install
tool/install.sh --prefix %{_prefix} --destdir %{buildroot}
# Fedora keeps user units in /usr/lib/systemd/user.
mkdir -p %{buildroot}%{_prefix}/lib/systemd/user
mv %{buildroot}%{_datadir}/systemd/user/pangolin-session.target \
    %{buildroot}%{_prefix}/lib/systemd/user/
rmdir %{buildroot}%{_datadir}/systemd/user %{buildroot}%{_datadir}/systemd

install -Dpm 0644 packaging/rpm/pangolin.pam %{buildroot}%{_sysconfdir}/pam.d/pangolin
install -Dpm 0644 packaging/rpm/pangolin.logrotate %{buildroot}%{_sysconfdir}/logrotate.d/pangolin
install -Dpm 0644 packaging/rpm/pangolin.tmpfiles %{buildroot}%{_prefix}/lib/tmpfiles.d/pangolin.conf
install -dm 0755 %{buildroot}%{_localstatedir}/lib/pangolin
install -dm 1777 %{buildroot}%{_localstatedir}/lib/pangolin/users

install -Dpm 0644 packaging/rpm/greetd-pangolin.toml %{buildroot}%{_sysconfdir}/greetd/pangolin.toml
install -Dpm 0644 packaging/rpm/greetd-pangolin.conf \
    %{buildroot}%{_prefix}/lib/systemd/system/greetd.service.d/pangolin-greeter.conf
install -Dpm 0644 packaging/rpm/plymouth-quit-pangolin.conf \
    %{buildroot}%{_prefix}/lib/systemd/system/plymouth-quit.service.d/pangolin-greeter.conf
install -Dpm 0644 packaging/rpm/pangolin-greeter.sysusers \
    %{buildroot}%{_prefix}/lib/sysusers.d/pangolin-greeter.conf
install -Dpm 0644 packaging/rpm/pangolin-greeter.tmpfiles \
    %{buildroot}%{_prefix}/lib/tmpfiles.d/pangolin-greeter.conf
install -dm 0700 %{buildroot}%{_localstatedir}/lib/pangolin-greeter
install -dm 0755 %{buildroot}%{_localstatedir}/log
touch %{buildroot}%{_localstatedir}/log/Pangolin.log
touch %{buildroot}%{_localstatedir}/log/PangolinGreeter.log

%post
# The session's log, writable by the user installing the package (other
# users' sessions log to ~/.local/state/pangolin/Pangolin.log).
[ -e %{_localstatedir}/log/Pangolin.log ] || install -m 0644 /dev/null %{_localstatedir}/log/Pangolin.log
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ] && getent passwd "$SUDO_USER" >/dev/null; then
    chown "$SUDO_USER:" %{_localstatedir}/log/Pangolin.log || :
fi
gtk-update-icon-cache -q -f -t %{_datadir}/icons/hicolor >/dev/null 2>&1 || :

%pre greeter
getent group pangolin-greeter >/dev/null || groupadd -r pangolin-greeter
getent passwd pangolin-greeter >/dev/null || \
    useradd -r -g pangolin-greeter -d %{_localstatedir}/lib/pangolin-greeter \
        -s /usr/sbin/nologin -c "Pangolin login screen" pangolin-greeter
for group in video render input; do
    getent group "$group" >/dev/null && usermod -a -G "$group" pangolin-greeter || :
done
exit 0

%post greeter
systemd-tmpfiles --create pangolin-greeter.conf >/dev/null 2>&1 || :
# greetd runs the login screen confined (xdm_t): its state is labeled like
# GDM's (/var/lib/gdm) so it can watch and replace its files.
if selinuxenabled >/dev/null 2>&1; then
    if command -v semanage >/dev/null 2>&1; then
        semanage fcontext -a -t xdm_var_lib_t '%{_localstatedir}/lib/pangolin-greeter(/.*)?' >/dev/null 2>&1 || \
            semanage fcontext -m -t xdm_var_lib_t '%{_localstatedir}/lib/pangolin-greeter(/.*)?' >/dev/null 2>&1 || :
        restorecon -R %{_localstatedir}/lib/pangolin-greeter >/dev/null 2>&1 || :
    else
        chcon -R -t xdm_var_lib_t %{_localstatedir}/lib/pangolin-greeter >/dev/null 2>&1 || :
    fi
fi
restorecon -R %{_localstatedir}/lib/pangolin >/dev/null 2>&1 || :
systemctl daemon-reload >/dev/null 2>&1 || :

%postun greeter
systemctl daemon-reload >/dev/null 2>&1 || :

%files
%license LICENSE
%{_datadir}/licenses/pangolin/
%doc README.md docs/PLATFORMS.md docs/DISTRIBUTING.md
%{_bindir}/pangolin
%{_bindir}/dahlia_apps
%{_bindir}/pangolin-session
%{_bindir}/pangolin-greeter
%{_prefix}/lib/pangolin/
%{_prefix}/lib/dahlia-apps/
%{_libexecdir}/pangolin/
%{_datadir}/applications/io.dahliaos.*.desktop
%{_datadir}/dbus-1/services/io.dahlia.DSettings.service
%{_datadir}/dbus-1/services/org.freedesktop.impl.portal.desktop.pangolin.service
%{_datadir}/xdg-desktop-portal/portals/pangolin.portal
%{_datadir}/wayland-sessions/pangolin.desktop
%{_datadir}/xdg-desktop-portal/pangolin-portals.conf
%{_datadir}/polkit-1/actions/io.dahliaos.logs.policy
%{_datadir}/pangolin/
%{_datadir}/icons/Pangolin/
%{_datadir}/icons/hicolor/*/apps/io.dahliaos.*.png
%{_prefix}/lib/systemd/user/pangolin-session.target
%{_prefix}/lib/tmpfiles.d/pangolin.conf
%config(noreplace) %{_sysconfdir}/pam.d/pangolin
%config(noreplace) %{_sysconfdir}/logrotate.d/pangolin
%config(noreplace) %{_sysconfdir}/xdg/xdg-desktop-portal-wlr/Pangolin
%dir %{_localstatedir}/lib/pangolin
%dir %attr(1777,root,root) %{_localstatedir}/lib/pangolin/users
%ghost %attr(0644,root,root) %{_localstatedir}/log/Pangolin.log

%files greeter
%config(noreplace) %{_sysconfdir}/greetd/pangolin.toml
%{_prefix}/lib/systemd/system/greetd.service.d/pangolin-greeter.conf
%{_prefix}/lib/systemd/system/plymouth-quit.service.d/pangolin-greeter.conf
%{_prefix}/lib/sysusers.d/pangolin-greeter.conf
%{_prefix}/lib/tmpfiles.d/pangolin-greeter.conf
%dir %attr(0700,pangolin-greeter,pangolin-greeter) %{_localstatedir}/lib/pangolin-greeter
%ghost %attr(0644,pangolin-greeter,pangolin-greeter) %{_localstatedir}/log/PangolinGreeter.log

%changelog
* Sat Oct 17 2026 Logan <loganctorres1@gmail.com> - 1.0.0-6
- Stronger, frosted blur (wider reach, more levels, grain), closer to
  dahliaOS's acrylic
- Windows that aren't focused draw their glass opaque (Settings toggle)
- Logs: journals with repeated fields load; terminal color codes stripped

* Sat Oct 17 2026 Logan <loganctorres1@gmail.com> - 1.0.0-5
- Media controls (MPRIS) in Quick Settings
- Overview close button takes clicks over its whole area
- Logs reads system and kernel logs after authorization (polkit policy for
  a read-only helper)
- Separate Mouse and Touchpad settings, touchpad acceleration
- Gallery welcome screen; Terminal tab bar follows a light terminal theme

* Sat Oct 17 2026 Logan <loganctorres1@gmail.com> - 1.0.0-4
- Window drags start from where the button was pressed (no stall and
  offset at the start of a drag)
- Restart the desktop portal at login so screen capture (OBS, browsers)
  works after switching sessions

* Fri Oct 16 2026 Logan <loganctorres1@gmail.com> - 1.0.0-3
- river retries frames the graphics driver refuses (i915 EBUSY), which made
  the pointer stutter
- Shell waits for a display instead of looping while none is connected

* Fri Oct 16 2026 Logan <loganctorres1@gmail.com> - 1.0.0-2
- Native file chooser and Open With dialog (xdg-desktop-portal backend)
- Hot corners; separate mouse and touchpad settings
- Seamless login from the greeter; greeter state labeled for SELinux
- Shell follows the screen when displays change; blur survives resume
- Interface font everywhere; new apps show up without logging out

* Wed Oct 14 2026 Logan <loganctorres1@gmail.com> - 1.0.0-1
- First package: Pangolin shell, dahliaOS apps, Pangolin's river and the
  greetd login screen
