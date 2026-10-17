<p align="center">
  <img width="80%" src="https://github.com/dahliaOS/brand/blob/master/pangolin/svg/logotypewhitetext.svg#gh-dark-mode-only" />
  <img width="80%" src="https://github.com/dahliaOS/brand/blob/master/pangolin/svg/logotypeblacktext.svg#gh-light-mode-only" />
</p>
 
<p align="center">
<a href="https://dahliaos.io">Website</a> •
<a href="https://dahliaos.io/discord">Discord</a> •
<a href="https://dahliaos.io/download">Releases</a> •
<a href="https://dahliaos.io/donate">Donate</a> •
<a href="https://docs.dahliaos.io">Documentation</a>

# Pangolin Desktop
[![Build and Deploy to Web](https://github.com/dahliaOS/pangolin_desktop/actions/workflows/web.yml/badge.svg)](https://github.com/dahliaOS/pangolin_desktop/actions/workflows/web.yml)
[![Locale generator](https://github.com/dahliaOS/pangolin_desktop/actions/workflows/locale_gen.yml/badge.svg)](https://github.com/dahliaOS/pangolin_desktop/actions/workflows/locale_gen.yml)
[![Demo](https://img.shields.io/website?label=Web%20Build&url=https%3A%2F%2Fweb.dahliaos.io&style=for-the-badge)](https://web.dahliaos.io)
[![Crowdin](https://badges.crowdin.net/e/1a53a75fb38f15843d4eb6d9b9e4215a/localized.svg?style=for-the-badge)](https://translate.dahliaos.io/pangolin)

 - 🖥 **Pangolin** is the desktop shell of dahliaOS.
 - 💙 **Written** in Dart/Flutter.
 - 🏝 **[Utopia](https://github.com/dahliaOS/utopia)** is the window manager of Pangolin.
 - 🐚 **Pangolin** was named after a shelled animal like the [Armadillo UI](https://9to5google.com/2018/12/26/fuchsia-armadillo-ui-gone/).
 - 🌐 **Check** the web preview [here](https://web.dahliaos.io).

<p align="center">
  <img width="100%" src="https://docs.dahliaos.io/docs/pangolin/settings.webp"
</p>

> Settings and start menu, commit [876180d](https://github.com/dahliaOS/pangolin_desktop/commit/876180df15d3b6c8720fb7474d1bcf1b5202fc67).

<p align="center">
  <img width="100%" src="https://docs.dahliaos.io/docs/pangolin/search.webp"
</p>

> Calculator, Terminal, Notes and search, commit [876180d](https://github.com/dahliaOS/pangolin_desktop/commit/876180df15d3b6c8720fb7474d1bcf1b5202fc67).

## Pangolin as a desktop session

Pangolin runs as a full Wayland desktop on top of the
[river](https://codeberg.org/river/river) compositor (0.6, non-monolithic):
river composites and handles input, Pangolin is its window manager and shell,
and the dahliaOS apps run as regular Wayland clients.

### What's included

| Component | What it is |
| --- | --- |
| **Pangolin** (`pangolin`) | Shell (taskbar, launcher, search, quick settings, notifications, overview, power menu) and window manager |
| **dahliaOS apps** (`dahlia_apps <app>`) | Settings, Files (tabbed), App Store (Flathub), Clock, Welcome, Terminal (tabbed), Calculator, Activity Monitor, Gallery, Text Editor, Logs |
| **dsettingsd** | The `io.dahlia.DSettings` settings daemon shared by the shell and the apps |
| **pangolin-session** | Session launcher: environment, D-Bus, river, autostart, shell supervision |

### How it fits together

```
 river (compositor) ──river-window-management-v1──▶ Pangolin (WM + shell)
   │                  river-xkb-bindings / layer-shell / input-management
   │
   ├── Pangolin desktop surface  (layer-shell BACKGROUND: wallpaper)
   ├── Pangolin shell surface    (layer-shell TOP: taskbar, overlays; click-through
   │                              outside its widgets via an input region)
   └── app windows (xdg-shell) ─ dahlia_apps, flatpaks, any Wayland app
```

* `packages/wayland` is a pure-Dart Wayland client (protocol bindings are
  generated from the XML in `packages/wayland/protocols`). Pangolin's river
  window manager lives in `lib/services/wm/river.dart`.
* The two Pangolin surfaces are two Flutter views of one engine
  (`linux/my_application.cc`, gtk-layer-shell). Without a layer-shell
  compositor, or with `--windowed`, Pangolin runs in a normal window using its
  built-in Utopia window manager (handy for development).
* The apps are one Flutter project (`apps/`) built as a multi-call binary; each
  app gets its own Wayland app id (`io.dahliaos.<app>`) and desktop entry.
* Settings live in the `pangolin` dsettings table (scheme extended by
  `packages/pangolin_settings`), so changes made in Settings apply live to the
  shell and every app.

### Requirements

* Flutter (stable) and the Linux desktop toolchain: `clang cmake ninja-build pkg-config libgtk-3-dev`
* `libgtk-layer-shell-dev`, `libxkbcommon-dev`, `libepoxy-dev`, `libwayland-dev`
* river 0.6 (`zig` 0.16, wlroots 0.20, wayland-protocols, libevdev, pixman; see `river-main/river/README.md`):

  ```
  cd river-main/river && zig build -Doptimize=ReleaseSafe -Dxwayland --prefix ~/.local install
  ```
* At runtime (optional, features degrade gracefully without them): PAM (lock
  screen), polkit (permission prompts), `wpctl` (volume), `brightnessctl`,
  `flatpak` and PackageKit (App Store), `wl-copy` (copying screenshots),
  xdg-desktop-portal-wlr (screen sharing and recording), NetworkManager
  (network and VPN, `nm-connection-editor` to edit VPNs), `pw-dump` from
  PipeWire's tools (screen recording and microphone indicators), BlueZ,
  UPower, power-profiles-daemon and greetd (login screen).
* ARM64, Alpine Linux and other distributions: see
  [docs/PLATFORMS.md](docs/PLATFORMS.md).

### Build and install

```
tool/build.sh                 # release builds of the shell, the apps and dsettingsd
tool/install.sh               # installs into ~/.local (use --prefix /usr/local as root)
```

Then start a session:

* from a TTY: `~/.local/bin/pangolin-session`
* inside another desktop, in a window: `~/.local/bin/pangolin-session --nested`
* from a display manager: copy `share/wayland-sessions/pangolin.desktop` from
  the prefix to `/usr/share/wayland-sessions/` (installs to `/usr` or
  `/usr/local` are picked up directly).

`tool/install.sh --uninstall` removes an installation. The session restarts
the shell if it crashes and ends cleanly on **Sign out** (power menu).

Nothing is printed to the console: the session logs to
`/var/log/Pangolin.log` (system-wide installs, writable by the user who ran
`sudo tool/install.sh`) or `~/.local/state/pangolin/Pangolin.log`, and the
login screen to `/var/log/PangolinGreeter.log`. `PANGOLIN_LOG=-` keeps the
output on the terminal.

#### Fedora packages

```
tool/dist.sh                  # source tarball: dist/pangolin-desktop-VERSION.tar.xz
tool/rpm.sh                   # RPMs built from it: dist/*.rpm
sudo dnf install dist/pangolin-desktop-*.x86_64.rpm dist/pangolin-desktop-greeter-*.x86_64.rpm
```

`tool/rpm.sh` needs `rpmbuild` (`sudo dnf install rpm-build`, or `sudo apt
install rpm` in a Debian toolbox) besides what `tool/build.sh` needs. The
spec is `packaging/rpm/pangolin-desktop.spec`; `pangolin-desktop-greeter` is
the login screen (it points greetd at it). Pangolin's river goes to
`/usr/libexec/pangolin`, so it doesn't clash with Fedora's `river` package.

#### Login screen

`sudo tool/install.sh --prefix /usr/local --greeter` sets up Pangolin's login
screen for greetd, as GDM does for GNOME:

* it runs as its own user, `pangolin-greeter` (home `/var/lib/pangolin-greeter`),
  with GNOME's Adwaita pointers;
* it shows the wallpaper of the selected user and uses the display setup of
  the user who logged in last: sessions share both in `/var/lib/pangolin/users`
  (falling back to `/etc/xdg/monitors.xml`, GNOME's configuration);
* it keeps the boot splash on screen until it appears and fades out to black
  when you log in, the desktop then fading in, without showing the text
  console in between;
* the lock screen checks passwords with the distribution's password-only PAM
  stack (`/etc/pam.d/pangolin`), not with the fingerprint reader.

Switch to it with `sudo systemctl disable gdm && sudo systemctl enable greetd`.

#### System-wide

Build as your normal user and only install as root. `pangolin-session` uses
the river installed in its own prefix when there is one, so install river there
too:

```
cd river-main/river
DESTDIR="$PWD/stage" zig build -Doptimize=ReleaseSafe -Dxwayland --prefix /usr/local install
sudo cp -r stage/usr/local/. /usr/local/
cd ../..
tool/build.sh --clean           # --clean: first build on this machine
sudo tool/install.sh            # as root the prefix defaults to /usr/local
```

GDM and SDDM list sessions from `/usr/local/share/wayland-sessions`, so
**Pangolin** shows up on the login screen. Remove a per-user install first
(`tool/install.sh --uninstall`): its desktop entries in `~/.local/share` would
shadow the system-wide ones. `sudo tool/install.sh --uninstall` removes the
system-wide install (river's files are separate).

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| <kbd>Super</kbd> / <kbd>Super</kbd>+<kbd>A</kbd> | Launcher |
| <kbd>Super</kbd>+<kbd>S</kbd> / <kbd>Super</kbd>+<kbd>Space</kbd> | Search |
| <kbd>Super</kbd>+<kbd>Tab</kbd> | Overview |
| <kbd>Alt</kbd>+<kbd>Tab</kbd> / <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>Tab</kbd> | Switch windows |
| <kbd>Super</kbd>+<kbd>D</kbd> | Show desktop |
| <kbd>Super</kbd>+<kbd>E</kbd> / <kbd>Super</kbd>+<kbd>T</kbd> / <kbd>Super</kbd>+<kbd>I</kbd> | Files / Terminal / Settings |
| <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Esc</kbd> | Activity Monitor |
| <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>Del</kbd> / <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>E</kbd> | Power menu (sign out, restart, …) |
| <kbd>Super</kbd>+<kbd>Q</kbd> / <kbd>Alt</kbd>+<kbd>F4</kbd> | Close window |
| <kbd>Super</kbd>+<kbd>↑</kbd> / <kbd>↓</kbd> | Maximize / restore or minimize |
| <kbd>Super</kbd>+<kbd>←</kbd> / <kbd>→</kbd> | Snap to the left / right half |
| <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>F</kbd> | Fullscreen |
| <kbd>Super</kbd>+drag / <kbd>Super</kbd>+right-drag | Move / resize a window |
| <kbd>Print</kbd> | Screenshot to `~/Pictures/Screenshots` |

Files and Terminal have tabs: in Files, <kbd>Ctrl</kbd>+<kbd>T</kbd> opens a tab,
<kbd>Ctrl</kbd>+<kbd>W</kbd> closes it, <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>T</kbd>
reopens the last closed one, <kbd>Ctrl</kbd>+<kbd>Tab</kbd> /
<kbd>Ctrl</kbd>+<kbd>PgUp</kbd>/<kbd>PgDn</kbd> and <kbd>Alt</kbd>+<kbd>1</kbd>…<kbd>9</kbd>
switch tabs, and middle-clicking a folder (or **Open in New Tab**) opens it in
the background. Tabs can be reordered by dragging. Terminal uses
<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>T</kbd> / <kbd>W</kbd> for new / close.

## Development

To develop and locally test Pangolin:

### Step 1. Install development tools

1. Install [Flutter](https://docs.flutter.dev/get-started/install)
2. Install an IDE of your choice (we recommend [VSCode](https://code.visualstudio.com/))
    * We also recommend installing Dart and Flutter extensions if you're opting in for VSCode.
    For other IDEs, please inform yourself.

### Step 2. Run Pangolin

**Note**: You can run Pangolin on any platform that Flutter supports but we recommend running it on Linux as some features of Pangolin are designed exclusively for Linux and won't work on other platforms.

Run Pangolin by running:

```
make run target=linux
```

On Linux this starts Pangolin in a window with its built-in window manager.
The apps are developed the same way: `cd apps && flutter run -d linux -a files`
(the first argument picks the app). To test the full session, see
[Pangolin as a desktop session](#pangolin-as-a-desktop-session).

List of targets:
- linux
- windows
- macos

Flutter has hot reloading so no need to restart the instance when it's running!

## Contribute

If you're wondering how to contribute to the project, please refer to [CONTRIBUTING.md](/CONTRIBUTING.md)

## Translate

If you're interested in translating Pangolin, click [here](https://github.com/dahliaOS/pangolin_desktop/blob/main/CONTRIBUTING.md#translations) for more information on how to do so!


## License

<p align="left">
  <img width="30%" src="https://github.com/dahliaOS/brand/blob/main/dahliaOS/logotype/svg/logotype-dark.svg#gh-dark-mode-only"/>
  <img width="30%" src="https://github.com/dahliaOS/brand/blob/main/dahliaOS/logotype/svg/logotype-light.svg#gh-light-mode-only"/>
</p>

Copyright @ 2019-2023 - The dahliaOS Authors - contact@dahliaos.io

This project is licensed under the [Apache 2.0 license](/LICENSE). The river
compositor in `river-main/river` (with Pangolin's changes) is GPL-3.0-only,
see its own licensing notes. For forking and redistributing Pangolin, see
[docs/DISTRIBUTING.md](docs/DISTRIBUTING.md).
