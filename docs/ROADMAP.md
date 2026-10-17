# Pangolin roadmap (spec of 2026-10-16)

Working list for the "Comprehensive Bug Fix, Optimization, and Feature
Specification". Status: `[x]` done and verified, `[~]` code written (needs
build/test), `[ ]` not started. Notes say where the work lives.

Global targets: smooth on a 2016 dual-core with integrated graphics, and at
3840x2160@165 Hz like GNOME. Stack: Flutter/Dart (shell, dahlia_apps), GTK,
pkexec/polkit, D-Bus, PipeWire, UDisks2. The patched Flutter engine (high
refresh rate) comes after this list.

## Carried over from the previous request

- [x] File chooser portal (verified through xdg-desktop-portal and direct calls): UI (`apps/lib/kit/file_chooser.dart`, windows
      `dahlia_apps file_chooser|app_chooser` in `apps/lib/apps/portal/`);
      daemon `session/portal` (org.freedesktop.impl.portal.FileChooser +
      AppChooser), `.portal` file, D-Bus service, portals.conf, build/install.
- [~] Parent window of portal dialogs: xdg-foreign v1 in river
      (`river/Server.zig`), `setParent` in `apps/linux/runner`.
- [~] install.sh: remove a stale per-user (~/.local) install when installing
      system-wide (it shadowed the new Settings, desktop entries and cursors).
- [~] Greeter state dir SELinux label (xdm_var_lib_t, like /var/lib/gdm):
      install.sh `--greeter` and the RPM `%post` (semanage, else chcon).
- [~] RPM spec: portal files, SELinux %post; 1.0.0-2 built for fc44 and
      fc45 (`FEDORA=44 tool/rpm.sh`), [ ] not install-tested.
- [x] Hot corners (shell `_HotCorners` in session_commands.dart, Settings >
      Appearance > Hot corners).
- [~] Shell surfaces move to the new primary output / come back when their
      output goes away (`remapSurfaces`, delete-event in linux runner).
- [~] Native blur survives surface re-creation (`session/native/river_blur.cc`).

## 1. Greeter, shell performance, seamless login

- [~] 1.1 Greeter lag: no desktop surface in greeter mode, light text
      shadows, SELinux label (dsettingsd crash); [ ] measure at 4K 1.5x.
- [~] 1.2 Wallpaper of the selected user right away; on success the
      darkening goes at once, the UI fades, the wallpaper stays; the session
      starts on it without fading (PANGOLIN_FROM_GREETER).
- [~] 1.3 Greeter uses the Pangolin cursor theme (with Adwaita hands).
- [ ] 1.4 Wi-Fi and Bluetooth in the greeter (connect before login, pair a
      keyboard or mouse). Note: networks joined there must be saved for all
      users with system-owned secrets, since there's no user keyring yet.
      Check the polkit rules for the pangolin-greeter user, and SELinux
      (xdm_t) talking to NetworkManager and BlueZ.
- [ ] 1.5 GNOME Keyring: unlocked at login, so Wi-Fi/VPN secrets, browsers
      and Git don't ask for the keyring password. Fedora's greetd and
      gdm-password PAM files (/usr/lib/pam.d) already run
      pam_gnome_keyring (auth + session auto_start), and the user units
      gnome-keyring-daemon.socket and gcr-ssh-agent.socket exist.
      Check first:
      - In a real session, is org.freedesktop.secrets unlocked? The
        session only starts its own bus (dbus-run-session,
        pangolin-session.in:120) without DBUS_SESSION_BUS_ADDRESS. A private
        bus would start a second, locked daemon.
      - Export SSH_AUTH_SOCK (gcr-ssh-agent).
      - Do the unlock prompts (gcr-prompter) show? D-Bus-activated services
        need WAYLAND_DISPLAY (`systemctl --user import-environment`).
      - Autologin leaves the keyring locked.
      The lock screen (pam.d/pangolin) doesn't need it, since the keyring
      stays unlocked.

## 2. Displays

- [~] 2.1 Blur/popup animations after plugging in a display. Swapping the
      only display: outputs off/on verified headless; unplugging with no
      display left no longer loops remapping (n_monitors guard in the
      linux runner), [ ] not tested on a real unplug.
- [~] 2.2 Blur after suspend/resume: river ignores textures of the lost
      renderer and resets cutout buffers (Blur.zig textureOf, dropBuffers).

- [x] 2.3 Window corners square on the real machine: gone once the
      frame retry (3.3) was installed, with no corner code changed. Most
      likely the same dropped frames.
- [~] 2.4 OBS (Flatpak and native) offers no PipeWire screen capture;
      the microphone works. Config is fine (pangolin-portals.conf:
      ScreenCast=wlr; xdg-desktop-portal-wlr installed). Seen live
      2026-10-16:
      - The xdg-desktop-portal frontend running at 20:58 was started at
        19:16:33, by the previous session. It survives logout (unit not
        bound to graphical-session.target), and it may have been
        D-Bus-activated before pangolin-river-init's import-environment.
        Either way it may not have XDG_CURRENT_DESKTOP=Pangolin, so it
        wouldn't load pangolin-portals.conf.
      - xdg-desktop-portal-wlr wasn't running.
      Fix: restart xdg-desktop-portal after import-environment in
      pangolin-river-init (and stop it on exit). Then check that xdpw
      reaches river's screencopy (wlr-screencopy or
      ext-image-copy-capture) and OBS lists "Screen Capture (PipeWire)".
      Quick test: `systemctl --user restart xdg-desktop-portal`, then
      restart OBS. Confirmed by the user 2026-10-16: that brings capture
      back. Permanent: pangolin-river-init try-restarts xdg-desktop-portal
      and -wlr after importing the environment (1.0.0-4); [ ] confirm on
      the machine after a re-login.
- [ ] 2.5 Screen share picker (requested 2026-10-16): a dahliaOS dialog for
      choosing what to share: a screen, a window, or a selected area if
      possible. Thumbnails preferred.
      Today xdg-desktop-portal-wlr (0.8.4) has `chooser_type=none` in
      /etc/xdg/xdg-desktop-portal-wlr/Pangolin (whole output, no
      question). River already offers output and toplevel capture sources
      (ext-image-copy-capture, ext-foreign-toplevel-list in Server.zig).
      Route: `chooser_type=dmenu` with `chooser_cmd` pointing at a
      `dahlia_apps screen_share` picker. Verify xdpw's chooser line format
      for windows. Selected area: xdpw has no region mode, so it would need
      cropping, or Pangolin's own ScreenCast backend in session/portal
      (PipeWire).

## 3. Performance

- [x] 3.3 Pointer stutters over the desktop (any scale; smooth while
      dragging). Live log: i915 refuses commits on DP-9 with EBUSY (GNOME
      too, but mutter retries). River dropped the frame and waited for the
      next change. Now Output.zig retries after 1 ms (at most 10 times).
      Confirmed on the machine 2026-10-16: smooth at 1.5; about 1,160
      refusals in a few minutes, nearly all fixed by one retry. Logs only
      when it gives up. Shipped in 1.0.0-3.

- [ ] 3.1 Files (and other heavy apps) lagging the desktop: list rendering,
      watchers, rebuilds.
- [ ] 3.2 60 fps on 2016 hardware: batch status polling, fewer rebuilds.
- Measured 2026-10-16 (headless, Intel RPL-P iGPU, 3840x2160 at 1.5,
  PANGOLIN_PROFILE=frames, now also logged by dahlia_apps): steady frames
  are cheap (shell raster ~0.4-2 ms, Files scrolling 1113 items 0.6 ms, no
  frame over 16.7 ms); the hitches are first opens (overview 55 ms,
  launcher 28 ms, Files 43 ms: shader compiles, icon decodes). Flutter is
  paced at 60 Hz (GTK embedder) on any display. The user runs one display
  at a time; the external 4K one is on the Intel iGPU (card1 DP-9), so this
  matches their setup apart from the real 165 Hz scanout. Not measured:
  internal panel (its eDP connector is on the NVIDIA card), 2016 hardware.

## 4. Apps

- [x] 4.1 Media controls (MPRIS) in Quick Settings: lib/services/mpris.dart
      (players on the session bus, properties via PropertiesChanged,
      position from Seeked/reads, counted on while playing) and
      widgets/qs_media_card.dart (art, title, artist, seek bar, previous/
      play-pause/next, player switch when several). ZenitSlider gained
      onChangeEnd. Verified headless with a fake MPRIS player:
      PlayPause, Next, SetPosition calls and the card updates.
- [ ] 4.2 Disks: a dahliaOS app over UDisks2 with GNOME Disks' feature
      set (decided by the user 2026-10-16; GNOME Disks is not used).
      - Drives and partition map.
      - Mount and unmount; power off and eject.
      - Format a disk (partition table) and format partitions.
      - Create, delete, resize and edit partitions (type, name, flags).
      - LUKS: unlock, lock, change passphrase.
      - Mount options (fstab) and encryption options (crypttab).
      - Check and repair a filesystem.
      - Create and restore disk images.
      - SMART data and self-tests; benchmark.
      - Drive settings: standby, APM, write cache.
      Destructive steps get a confirmation that names the disk and its
      contents.
- [ ] 4.3 Archive Manager: a dahliaOS app in dahlia_apps (decided by the
      user 2026-10-16, no File Roller substitute). Open and browse,
      extract (all or selected), create and add files; zip, 7z, tar.*
      (gz, xz, zst, bz2), rar extract. Files integration: Open With,
      Extract Here, Compress…
- [x] 4.4 Gallery opens on "Welcome to Gallery" (app icon, Open Folder) when
      started without a folder or picture; Open Folder shows the folder
      chooser at Pictures (verified headless 2026-10-17). The empty-state
      button is no longer outlined.
- [x] 4.5 Logs asks for authorization (pkexec) for kernel/system logs.
      Decided 2026-10-16: pkexec only the readers, never the GUI itself.
      - libexec/pangolin/pangolin-read-logs: fixed read-only commands,
        journal, journal-follow (stops when its input closes; the app
        can't signal root) and kernel.
      - polkit action io.dahliaos.logs.read (auth_admin_keep, exec.path =
        the helper) in /usr/share/polkit-1/actions: install.sh for system
        installs, RPM %files.
      - Logs offers Authorize when dmesg is restricted, and "Show system
        messages" when journalctl hints at a partial journal (non-wheel
        users).
      Verified headless with a fake pkexec (refused and allowed). The real
      polkit prompt is untested.
      Fixed after 1.0.0-5 (user report): one audit entry with a repeated
      field (journalctl JSON gives a list of strings) threw a cast error and
      replaced the whole list with "Couldn't read logs". Lists are now
      decoded as bytes only when they're numbers. Messages also lose
      terminal color codes (gdm-session-worker's). Checked on this
      machine's journal.
- [ ] 4.6 Activity Monitor: Settings-style sidebar, Run task (Ctrl+R, in
      terminal option), field styling/alignment, polling off the UI thread.
- [ ] 4.7 Video Player: a dahliaOS app (requested 2026-10-16) that looks
      native (DahliaTitlebar, Zenit UI, no borders).
      - Playback with hardware decoding.
      - Seek bar, volume, speed, fullscreen.
      - Subtitle and audio track pickers.
      - Recent files.
      - Drag and drop; Open With from Files.
      - MPRIS, so the 4.1 media controls work.
      - Inhibit idle while playing.
      No video package in apps/pubspec.yaml yet; pick a libmpv-based
      player (e.g. media_kit) so codecs come from the system.

## 5. Files, desktop icons, associations

- [ ] 5.1 Papirus icons (beige folders) ONLY USED FOR FILE ICONS. The rest of the icons will remain the ones unique to Pangolin.
      The same file icons on the desktop (5.3).
- [~] 5.2 Open With… in Files; [ ] Settings > Apps default apps per type.
- [ ] 5.3 Desktop icons: ~/Desktop's files and folders on the desktop with the
      Papirus file icons (5.1), hideable (toggle in shell settings).
      Files and folders in Files and on the desktop (requested 2026-10-17):
      - draggable: drag and drop between Files windows, the desktop and
        other apps;
      - resizable: icon size;
      - selectable: click, Ctrl/Shift, rubber-band;
      - movable: rearranged on the desktop, moved between folders.
- [x] 5.4 New apps appear without re-login (rename events, late dirs,
      icon rescans) in `lib/services/application.dart`, `icon.dart`.
      Verified headless: an rpm-style rename and a flatpak exports folder
      created after login both show in search within the 5 s poll.
- [ ] 5.5 Files sidebar places editable (add, remove, rename, reorder) instead of
      hardcoded (`FileOps.userPlaces` in `apps/lib/apps/files/file_ops.dart`).
      Plan: keep them in the GTK bookmarks file (~/.config/gtk-3.0/bookmarks),
      which the file chooser and other file managers already read.
      Bugs seen in the code so far:
      - The list is read once per window.
      - English labels even for renamed or localized folders.
      - A folder disabled in xdg-user-dirs (set to "$HOME/") still shows
        under its own name and opens Home.
      User report: only Documents and Downloads open. Not reproduced
      2026-10-16: every place opens in the headless session, including the
      user's layout (Desktop with only a KDE .directory, empty Music, real
      pictures and videos). Pangolin isn't installed on the Fedora 45 host;
      an old copy with builds from 2026-10-13 is in
      ~/Documents/Codebase/pangolin_desktop-main. Waiting on what
      "fail to open" looks like.

## 6. GTK theme, accents, fonts

- [ ] 6.1 dahliaOS GTK theme ("Adwaita edits", GTK 3/4, light/dark),
      selectable in Appearance. Decided by the user 2026-10-16: GTK apps
      must look almost identical to a dahliaOS app (Zenit UI): colors and
      accent, radii, header bars like DahliaTitlebar, buttons, entries,
      switches, lists without borders or dividers, Inter. libadwaita apps
      ignore gtk-theme, so GTK 4 needs ~/.config/gtk-4.0/gtk.css with
      libadwaita's named colors.
- [ ] 6.2 Accent from the wallpaper; custom accent picker.
- [x] 6.4 Stronger, frosted blur like dahliaOS (user request 2026-10-17).
      dahliaOS's acrylic: two 32-sigma Gaussian blurs, 80% tint, 2% noise.
      river's blur (Blur.zig) now reads 96 px around each region and crops
      (title bars no longer run out of halvings at 40 px tall), uses up to
      6 halvings, and lays a 128 px grain tile under the client's tint.
      Headless: what used to show through Settings' title bar (Files'
      tabs) is gone; grain visible.
- [x] 6.5 Inactive windows opaque (toggle "Opaque inactive windows" in
      Settings > Appearance, on by default; opaque_inactive_windows).
      dahlia apps: ZenitBlur.effects follows the window's focus (kit/app.dart
      _WindowFocus). Shell-drawn title bars: translucent only when focused.
      Headless: Files' title bar is solid when unfocused, frosted when
      focused. Shell-drawn bars untested (no non-dahlia app headless).
- [~] 6.3 Interface font everywhere (component themes, overlays, button base);
      [ ] also GTK/child processes (font-name).

## 7. Quick Settings and Settings

- [~] 7.1 QS settings and edit buttons aligned side by side.
- [~] 7.2 Slider chevrons open Settings > Displays / Sound.
- [ ] 7.3 Sound: speaker test, sound theme (Yaru default, RPM dependency,
      login chime). Equalizer cut by the user 2026-10-16.
- [x] 7.4 Mouse and touchpad settings separate: Settings has Mouse and
      Touchpad pages ("mouse", "touchpad"; Touchpad shows "No touchpad
      found" without one), and touchpad acceleration
      (touchpad_acceleration, applied in lib/services/input.dart). Pages
      verified headless; the libinput side is untested (no touchpad
      headless).
- [ ] 7.5 Shell settings: taskbar autohide and size, app menu (fullscreen
      toggle, sorting), no placeholder profile picture. Taskbar
      left/right/top positions come later (decided 2026-10-16).
- [ ] 7.6 QS accounts: list sessions; Switch Account only to sessions
      already running (loginctl activate). greetd can't start a second
      login (decided 2026-10-16).
- [ ] 7.7 Bluetooth page in Quick Settings listing devices (connect,
      disconnect, battery), like the Wi-Fi page (`qs_network_page.dart`).

## 8. Window management and polish

- [ ] 8.1 Overview: drag a window past the desks for a new desktop (Shift:
      fullscreen there).
- [ ] 8.2 Desk switch gesture moves the whole plane; dot indicator overlay.
- [~] 8.3 Text ellipsized before trailing buttons (QS tiles).
- [x] 8.4 Terminal tab bar blur follows a light terminal theme: the window
      theme takes its brightness from the terminal theme's background
      (terminal.dart). Verified headless with "light" at 85% opacity.
- [x] 8.5 Welcome screen text (root cause: Zenit body styles ellipsized
      every paragraph after one line; body text wraps now).
- [ ] 8.6 Lock screen animates back to the desktop.
- [x] 8.8 Overview close button hard to hit (user report 2026-10-17). It sat
      half outside its window's slot, and Flutter only hit-tests inside a
      widget's bounds: half the button ignored clicks, and moving onto it
      left the slot and hid it. Now the slot reaches 24 px past the window,
      one hover region decides from geometry (window, or the button
      while shown), the button is 32 px, and the overview tooltips ignore
      the pointer. Headless (one input device, hover → outer half → click):
      new build closes the window, 1.0.0-4 doesn't.
- [~] 8.7 Dragging a window: a short hitch right at the start, then smooth.
      Cause (timed in river 2026-10-17): the app (CSD title bar) asks to
      move only once its drag gesture is recognized, i.e. after the pointer
      has already moved. River counted the op from where the pointer was
      then, so that first movement was lost: the window stood still, then
      followed from an offset. River's share is ~3 ms.
      Fix: Cursor.press_x/y records each press; an op started while a
      button is held counts from the press (Seat.zig), so the first op
      frame catches up. Headless check (sc11: a 60 px first step, 300 px
      total): old river moved the window 240 px, new 300 px. [ ] Feel on
      the machine (1.0.0-4).
