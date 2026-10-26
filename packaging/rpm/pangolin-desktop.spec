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
Version:        1.1.0
Release:        27%{?dist}
Summary:        The dahliaOS desktop (Pangolin) on the river Wayland compositor

# Pangolin and the dahliaOS apps: Apache-2.0; river and the Papirus icons
# of Files: GPL-3.0-only (river's protocols MIT); bundled Flutter and Dart
# packages: BSD-3-Clause and MIT; Inter: OFL-1.1; Adwaita's hand pointers:
# CC-BY-SA-3.0. See docs/DISTRIBUTING.md.
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
# The default monospace font: Terminal, Text Editor, Logs.
Requires:       google-roboto-mono-fonts
Recommends:     xdg-desktop-portal-wlr
Recommends:     xdg-desktop-portal-gtk
Recommends:     polkit
Recommends:     udisks2
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
Summary:        Pangolin's login screen and display manager
Requires:       %{name} = %{version}-%{release}
Requires:       pam
Requires(pre):  shadow-utils
Requires(post): systemd
Recommends:     policycoreutils-python-utils

%description greeter
Pangolin's display manager (pangolin-dm, built like GDM: a daemon, a
privileged session worker per login, the login screen as its own user,
pangolin-greeter) and its login screen: it shows the selected user's
wallpaper and the display setup of their desktop, keeps the boot splash up
until it appears, and fades into the desktop.

Use it instead of GDM with:
  systemctl disable gdm && systemctl enable pangolin-dm

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

install -Dpm 0644 packaging/rpm/pangolin-dm.pam %{buildroot}%{_sysconfdir}/pam.d/pangolin-dm
install -Dpm 0644 packaging/rpm/pangolin-dm-greeter.pam %{buildroot}%{_sysconfdir}/pam.d/pangolin-dm-greeter
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
# pangolin-dm runs as xdm_t, as gdm does (the sessions it starts get their
# own contexts from pam_selinux).
if selinuxenabled >/dev/null 2>&1; then
    if command -v semanage >/dev/null 2>&1; then
        semanage fcontext -a -t xdm_exec_t '%{_libexecdir}/pangolin/pangolin-dm' >/dev/null 2>&1 || \
            semanage fcontext -m -t xdm_exec_t '%{_libexecdir}/pangolin/pangolin-dm' >/dev/null 2>&1 || :
        restorecon %{_libexecdir}/pangolin/pangolin-dm >/dev/null 2>&1 || :
    else
        chcon -t xdm_exec_t %{_libexecdir}/pangolin/pangolin-dm >/dev/null 2>&1 || :
    fi
fi
# The login screen runs confined (xdm_t): its state is labeled like
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

%preun greeter
# Removed for good: off as display manager (not stopped, which would end
# the session running under it).
if [ "$1" -eq 0 ]; then
    systemctl --no-reload disable pangolin-dm.service >/dev/null 2>&1 || :
fi

%postun greeter
systemctl daemon-reload >/dev/null 2>&1 || :

%files
%license LICENSE LICENSE.old
%{_datadir}/licenses/pangolin/
%{_datadir}/fonts/pangolin-inter/
%doc README.md docs/PLATFORMS.md docs/DISTRIBUTING.md
%{_bindir}/pangolin
%{_bindir}/dahlia_apps
%{_bindir}/pangolin-session
%{_bindir}/pangolin-greeter
%{_prefix}/lib/pangolin/
%{_prefix}/lib/dahlia-apps/
%{_libexecdir}/pangolin/
%exclude %{_libexecdir}/pangolin/pangolin-dm
%exclude %{_prefix}/lib/systemd/system/pangolin-dm.service
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
%{_sysconfdir}/xdg/autostart/pangolin-gtk-style-off.desktop
%dir %{_localstatedir}/lib/pangolin
%dir %attr(1777,root,root) %{_localstatedir}/lib/pangolin/users
%ghost %attr(0644,root,root) %{_localstatedir}/log/Pangolin.log

%files greeter
%{_libexecdir}/pangolin/pangolin-dm
%{_prefix}/lib/systemd/system/pangolin-dm.service
%config(noreplace) %{_sysconfdir}/pam.d/pangolin-dm
%config(noreplace) %{_sysconfdir}/pam.d/pangolin-dm-greeter
%{_prefix}/lib/systemd/system/plymouth-quit.service.d/pangolin-greeter.conf
%{_prefix}/lib/sysusers.d/pangolin-greeter.conf
%{_prefix}/lib/tmpfiles.d/pangolin-greeter.conf
%dir %attr(0700,pangolin-greeter,pangolin-greeter) %{_localstatedir}/lib/pangolin-greeter
%ghost %attr(0644,pangolin-greeter,pangolin-greeter) %{_localstatedir}/log/PangolinGreeter.log

%changelog
* Mon Oct 26 2026 Logan <loganctorres1@gmail.com> - 1.1.0-27
- Closed menus and popups no longer leave pieces of themselves on the
  desktop (dark rounded blocks that showed when a menu, Quick Settings or
  the launcher opened): two races in the shell's partial repaint let a
  frame's change reach only some of its buffers

* Mon Oct 26 2026 Logan <loganctorres1@gmail.com> - 1.1.0-26
- The login screen no longer draws its blurred wallpaper again for every
  frame (a caret's blink, a hover): it's on the desktop surface below the
  controls, composited only when it changes, a tenth of the GPU time a
  frame

* Mon Oct 26 2026 Logan <loganctorres1@gmail.com> - 1.1.0-25
- The login screen runs on the GPU that drives the built-in screen: on
  laptops with an NVIDIA GPU next to it, every frame crossed between them
  and waited for the NVIDIA GPU to wake up (hovers and clicks lagged)
- Windows dragged towards another monitor cross over instead of snapping
  to the side of the built-in screen; snapping and maximizing use the
  window's own monitor

* Mon Oct 26 2026 Logan <loganctorres1@gmail.com> - 1.1.0-24
- pangolin-dm holds the display devices between the login screen and the
  desktop itself (no console flash), so nothing of the login screen keeps
  its session and VT; the login screen's settings daemon stops with it
- PANGOLIN_PROFILE in pangolin-dm's environment reaches the login screen:
  frame timings in /var/log/PangolinGreeter.log

* Mon Oct 26 2026 Logan <loganctorres1@gmail.com> - 1.1.0-23
- pangolin-dm: logins work again. The session waits until logind has let
  go of the login screen's VT (its leftovers ended), and moves to a free VT
  when that stays taken, instead of starting without an active session
- river no longer retries a failing modeset without pause, which made the
  login screen crawl when its session wasn't active
- The login screen uses the selected user's font (1.1.0-22 fell back to
  DejaVu Sans); only fonts Flutter can draw are offered or used
- App title bars are blurred from the start, not only after a focus or
  size change; blur keeps its last image while what's behind it has no
  texture yet

* Sun Oct 25 2026 Logan <loganctorres1@gmail.com> - 1.1.0-22
- The login screen lists users again, systemd-homed ones included, with
  their avatars; it shows each user's wallpaper and interface font
- Requires google-roboto-mono-fonts: Roboto Mono is the default monospace
  font (Terminal, Text Editor, Logs)
- Terminal draws its cursor and selection in the accent color
- The hidden taskbar leaves no strip on screen
- Windows stay on their display after a scale or arrangement change, and
  come to the nearest display when theirs is unplugged
- Smooth pill selectors in Settings and Files at 100% scale

* Sun Oct 25 2026 Logan <loganctorres1@gmail.com> - 1.1.0-21
- pangolin-dm, Pangolin's own display manager (built like GDM: a daemon, a
  PAM session worker per login, the login screen as its own user), in the
  greeter package, which no longer requires greetd; off until enabled
  (systemctl disable gdm && systemctl enable pangolin-dm)

* Sun Oct 25 2026 Logan <loganctorres1@gmail.com> - 1.1.0-20
- Files' window body is opaque again: its window-sized blur flashed while
  the window was moved, resized, focused or animated

* Sun Oct 25 2026 Logan <loganctorres1@gmail.com> - 1.1.0-19
- Files redesigned after the dahliaOS design: tabs in the title bar, a
  navigation row with breadcrumbs and search, collapsible sidebar sections
  (Favourites, Drives, Cloud Drives), a toolbar with New and five views
  (Details, Tiles, Small, Medium and Large icons), resizable columns,
  colour tags, a translucent window
- Files: rubber-band selection, a selection mode, and dragging files onto
  folders, tabs and sidebar places (Ctrl copies)
- Files draws files and folders with Papirus icons, folders in beige
  (Papirus: GPL-3.0)

* Sun Oct 25 2026 Logan <loganctorres1@gmail.com> - 1.1.0-18
- River is back in the package: 1.1.0-17 was built without it and sessions
  didn't start; building a package without river now fails

* Sun Oct 25 2026 Logan <loganctorres1@gmail.com> - 1.1.0-17
- Disks: a dahliaOS app over UDisks2 (drives and partition map, mount,
  eject and power off, format, create/delete/resize/edit partitions, LUKS,
  mount and encryption options, check and repair, disk images, SMART and
  self-tests, benchmark, drive settings); Recommends udisks2
- dahliaOS look for GTK 3, GTK 4 and libadwaita apps, following the accent
  color and light/dark (Settings > Appearance > Other apps); kept out of
  other desktops
- Inter installed as a system font

* Sun Oct 25 2026 Logan <loganctorres1@gmail.com> - 1.1.0-16
- Saved logins work in Pangolin sessions: the session joins the user's
  session bus, where the GNOME Keyring unlocked at login runs, instead of
  a bus of its own with a second, locked keyring (apps asked to sign in
  again after every switch from GNOME). SSH keys come from the keyring's
  agent too
- The tray flyout no longer cuts a strip out of the taskbar, or drags a
  line along, while it opens and closes

* Sat Oct 24 2026 Logan <loganctorres1@gmail.com> - 1.1.0-15
- Clicks no longer stop working for good after a window closes while its
  title bar is held or dragged (common with Steam and other X11 apps);
  only logging out used to help

* Sat Oct 24 2026 Logan <loganctorres1@gmail.com> - 1.1.0-14
- System tray rewritten: works with AppIndicator / StatusNotifierItem apps
  (Discord, Steam, Nextcloud, KDE Connect, Telegram, applets). Pangolin
  runs the StatusNotifierWatcher or joins the running one, follows icon,
  status and tooltip changes, and shows the apps' own menus (submenus,
  checkboxes, radio items) in the shell's style. Left click activates (or
  opens the menu), middle click is the secondary action, the wheel scrolls
- Shell popups (app menu, tray, Quick Settings, notifications, right-click
  menus) no longer show stale pixels or flash old frames: the Flutter
  embedder lost the damage of frames presented while GTK was painting

* Sat Oct 24 2026 Logan <loganctorres1@gmail.com> - 1.1.0-13
- Settings > Displays: displays can be dragged to arrange them, snap
  against each other, and never overlap; an overlapping layout (from an
  older or GNOME configuration) is fixed when applied
- Taskbar: closing two apps at once no longer leaves one behind (an
  uncaught RangeError in the app list)
- Screenshots: Print freezes the screen and the tool opens on that still,
  so the overview, launcher, notifications, Quick Settings, the tray and
  right-click menus can be captured

* Sat Oct 24 2026 Logan <loganctorres1@gmail.com> - 1.1.0-12
- Activity Monitor: a sidebar like Settings' (Processes, CPU, Memory,
  Network, Disk), Run Task (Ctrl+R, optionally in Terminal), aligned
  process columns with full process names, and system polling off the UI
  thread
- Details lists (Settings > About and others) align their values at the
  right edge

* Mon Oct 19 2026 Logan <loganctorres1@gmail.com> - 1.1.0-11
- Login and lock screen no longer lag when typing: a keystroke or a
  blinking cursor redrew the whole screen; now only what changed is redrawn
  (in the apps too)
- Settings keeps ~/.config/monitors.xml (GNOME's format) up to date with
  the display setup

* Mon Oct 19 2026 Logan <loganctorres1@gmail.com> - 1.1.0-10
- Smoother animations at high refresh rates: the shell and the apps start
  every frame on time (their frames started up to 2 ms late, and the
  overview ran at half of 165 Hz)
- No black screen between the login screen and the desktop: its wallpaper
  stays up until the desktop shows the same

* Mon Oct 19 2026 Logan <loganctorres1@gmail.com> - 1.1.0-9
- Fixed: the lock screen turned the right password down at random (the
  password is now checked in a process of its own)
- New lock screen and login screen, as ChromeOS lays them out: blurred
  wallpaper, one password field, a shelf with power and the time
- Login screen: typing works without clicking the field first; it hands
  over to the desktop on the same wallpaper
- Escape closes the launcher and the other shell menus

* Mon Oct 19 2026 Logan <loganctorres1@gmail.com> - 1.1.0-8
- 4K smoothness: the shell no longer repaints the whole screen on clock
  ticks, taskbar animations, overview opening/closing and focus changes
  (a 10-25 ms hitch each); apps no longer repaint their whole window when
  they lose focus
- Dragging windows: a fast mouse no longer makes the window fall further
  and further behind until input is dropped
- The laptop panel turns back on when the only monitor in use is unplugged

* Mon Oct 19 2026 Logan <loganctorres1@gmail.com> - 1.1.0-7
- Fixed: the taskbar had no blur (river drew it below the screen and
  didn't see its own wallpaper behind it)
- Fixed: right-clicking the desktop did nothing (river only drew a pixel
  of the desktop surface, and only took clicks there)

* Sun Oct 18 2026 Logan <loganctorres1@gmail.com> - 1.1.0-6
- Overview at 4K: the shell no longer repaints the whole screen while the
  overview closes, desk thumbnails come from a small copy of the wallpaper
  (a freeze on every opening), and river draws the wallpaper itself
- Shell and apps: a full repaint no longer copies the whole window on the
  CPU first (GTK uploaded its empty background under every Flutter frame:
  ~20 ms per repaint at 4K)

* Sun Oct 18 2026 Logan <loganctorres1@gmail.com> - 1.1.0-5
- Pangolin's build of Flutter's Linux embedder for the shell and the apps:
  frames at the display's refresh rate (165 Hz) instead of 60, and only
  what changed is repainted and sent to the compositor
  (FLUTTER_LINUX_FPS=N or unlimited in ~/.config/pangolin/session.env)

* Sun Oct 18 2026 Logan <loganctorres1@gmail.com> - 1.1.0-4
- Fixed: the taskbar flashed at the top of the screen when the shell
  surface grew or shrank (river now moves a layer surface only once it
  has drawn its new size)

* Sun Oct 18 2026 Logan <loganctorres1@gmail.com> - 1.1.0-3
- 4K smoothness: the shell surface only covers the screen while something
  besides the taskbar is shown; before, every clock tick re-composited the
  whole 4K screen (a missed refresh each second)
- Hot corners are detected by river

* Sun Oct 18 2026 Logan <loganctorres1@gmail.com> - 1.1.0-2
- Profiling for the 4K investigation: with PANGOLIN_PROFILE=frames river
  logs GPU time per frame and what it draws
- ~/.config/pangolin/session.env (VAR=value lines) adds environment
  variables to Pangolin sessions

* Sat Oct 17 2026 Logan <loganctorres1@gmail.com> - 1.1.0-1
- Quick Settings: Bluetooth devices (connect, pair, battery) and Wi-Fi
  networks (connect, password prompt), real airplane mode
- Accent color from the wallpaper, or a custom color
- Lock screen fades back to the desktop when unlocking
- Taskbar size (small, medium, large) and hide automatically
- App menu: full screen grid, sort A to Z or by category, user avatar
  instead of a placeholder
- Window borders also on windows Pangolin decorates (verified)

* Sat Oct 17 2026 Logan <loganctorres1@gmail.com> - 1.0.0-7
- Optional hairline border around windows, macOS-like (Settings >
  Appearance > Window borders)
- dahliaOS app windows rounded at 12 px again (GTK's theme used 8 px)

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
