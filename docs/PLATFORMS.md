# Platforms

Pangolin isn't tied to a distribution: it needs a Linux system with
Wayland libraries, GTK 3 and a few desktop services, and degrades gracefully
when optional ones are missing. This page lists what it needs, and what is
different on ARM64 and on Alpine Linux (musl, busybox, OpenRC).

## Architectures

| | x86_64 | aarch64 (ARM64) |
| --- | --- | --- |
| Pangolin shell and apps (Flutter) | yes | yes, built on an ARM64 machine |
| river (Zig) | yes | yes |
| Dart helpers (`dsettingsd`, `pangolin-displays`) | yes | yes |

`tool/build.sh` and `tool/install.sh` pick Flutter's build directory
(`build/linux/x64` or `build/linux/arm64`) from `uname -m`. Flutter doesn't
cross-compile Linux desktop apps, so build on the target architecture (an
ARM64 laptop, a Raspberry Pi 5, an ARM64 VM or container).

On small GPUs (Raspberry Pi) turn off visual effects in Settings →
Appearance if animations stutter: blur is the most expensive effect.

## What Pangolin needs

To build:

- Flutter (stable) with its Linux toolchain: clang, cmake, ninja,
  pkg-config, GTK 3 development files
- gtk-layer-shell, epoxy and wayland-client development files
- Zig 0.16, wlroots 0.20, wayland, wayland-protocols, libinput, libevdev,
  libxkbcommon and pixman development files (for river)

To run:

| Needed for | Packages (names vary) | Without it |
| --- | --- | --- |
| everything | GTK 3, gtk-layer-shell, Mesa (EGL/GLES), libxkbcommon, libinput, wlroots 0.20, D-Bus (`dbus-run-session`) | — |
| starting the session | logind (systemd or elogind) or seatd | river can't open the screen and input devices |
| lock screen | PAM (`libpam.so.0`) | the screen never locks (it couldn't be unlocked) |
| permission prompts (installing software, ...) | polkit | apps can't ask for administrator rights |
| system packages in the App Store | PackageKit | only Flathub apps |
| Flathub apps | flatpak | the App Store can only browse |
| sound | PipeWire with WirePlumber (`wpctl`) | no volume control |
| screen sharing and recording (OBS, browsers) | xdg-desktop-portal, xdg-desktop-portal-wlr, xdg-desktop-portal-gtk | apps can't capture the screen |
| brightness | brightnessctl or a writable backlight | no brightness control |
| login screen | greetd | log in with another display manager (GDM, SDDM, ...) |
| VPNs in Quick Settings | NetworkManager (`nm-connection-editor` to edit them) | no VPN control |
| screen recording, microphone and camera indicators | `pw-dump` (PipeWire's tools, e.g. `pipewire-utils`) | only cameras opened directly are shown |
| copying screenshots | wl-clipboard (`wl-copy`) | screenshots are saved, not copied |

## Alpine Linux (musl)

Alpine works with a few differences. It hasn't been tested on Alpine
hardware yet: please report what breaks.

**glibc compatibility.** Flutter's engine and Dart's AOT runtime are built
against glibc. Install `gcompat` so the shell, the apps and the Dart helpers
can load:

```sh
apk add gcompat libstdc++
```

The Flutter SDK itself doesn't run on musl, so build the shell and the apps
on a glibc system (or in a glibc container, e.g. Debian with toolbox or
distrobox) and install the result on Alpine. river builds natively on
Alpine.

**Packages.**

```sh
apk add gtk+3.0 gtk-layer-shell mesa-dri-gallium mesa-egl libinput \
    libxkbcommon xkeyboard-config dbus linux-pam seatd polkit \
    pipewire wireplumber xdg-desktop-portal xdg-desktop-portal-wlr \
    xdg-desktop-portal-gtk musl-utils
# Optional: flatpak, brightnessctl, wl-clipboard, greetd, elogind,
# networkmanager, pipewire-tools.
# Building river: zig wlroots-dev wayland-dev wayland-protocols \
#     libinput-dev libevdev-dev libxkbcommon-dev pixman-dev pkgconf
```

Use Zig 0.16 from ziglang.org if your Alpine release packages another
version.

**Seat and session.** river opens the display and input devices through
libseat: either run `seatd` (`rc-update add seatd && rc-service seatd
start`, and add the user to the `seat` group) or use elogind.
`XDG_RUNTIME_DIR` must exist (elogind or `pam_rundir` create it).

**No systemd.** Pangolin notices and adapts:

- `graphical-session.target` isn't used; the desktop portals start through
  D-Bus activation instead.
- Locking before suspend needs logind's API, which elogind provides. Without
  it the screen still locks from the menu, Super+L and on idle.
- The Logs app reads `/var/log` (busybox `syslogd` writes
  `/var/log/messages`) when there's no journal, and falls back to plain
  `dmesg` output.
- Settings → Date & Time lists time zones from tzdata; changing it needs
  `setup-timezone` (as root) without `timedatectl`.

**busybox.** The session scripts are POSIX `sh` and only use options
busybox supports. `musl-utils` provides `getent` (the permission prompt also
reads `/etc/passwd` directly without it). `util-linux` is optional: its
`setpriv` makes river stop by itself if whatever started the session dies
abruptly.

## Other distributions

Pangolin is developed on Fedora and in a Debian container, and only uses
what any current distribution ships. Install it as described in the
README (`tool/install.sh`), with `--system-session` to list it in a
display manager, or `--greeter` to use Pangolin's login screen with
greetd.
