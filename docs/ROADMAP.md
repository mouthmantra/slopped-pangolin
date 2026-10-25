# Pangolin roadmap (spec of 2026-10-16)

Working list for the "Comprehensive Bug Fix, Optimization, and Feature
Specification". Status: `[x]` done and verified, `[~]` code written (needs
build/test), `[ ]` not started. Notes say where the work lives.

Global targets: smooth on a 2016 dual-core with integrated graphics, and at
3840x2160@165 Hz like GNOME. Stack: Flutter/Dart (shell, dahlia_apps), GTK,
pkexec/polkit, D-Bus, PipeWire, UDisks2. The patched Flutter engine (high
refresh rate) comes after this list.

**Priority order (user, 2026-10-17):** 1. 3.4 4K jitter, highest urgency.
2. The new apps (4.2 Disks, 4.3 Archive Manager, 4.6 Activity Monitor,
4.7 Video Player) and the requested changes to existing apps. 3. The GTK
theme (6.1).

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
- [~] 1.6 Complete greeter rewrite (user, 2026-10-18). Done 2026-10-19
      (lib/components/greeter, lib/components/login/login_kit.dart),
      [ ] real-hardware test (the user logs in with GDM since 2026-10-17;
      greetd's config.toml still pointed at /usr/local/bin/pangolin-greeter,
      which doesn't exist):
      - ChromeOS layout: blurred wallpaper (BlurredWallpaper's small copy,
        cheap at 4K), user pod, one pill field, other users as small pods,
        a shelf (Shut down, Restart, session) and a status pill (battery
        from sysfs, date, time). Account pictures from AccountsService.
      - river draws the selected user's wallpaper sharp (the greeter's
        splash, PANGOLIN_WALLPAPER=1 in pangolin-greeter, SplashCache
        writes it at the monitors' width and follows PANGOLIN_SPLASH); the
        greeter only blurs it. Logged in: content out, blur out, down to
        that sharp wallpaper, which the session starts on (same image).
      - Black gap between login and desktop (user, 2026-10-19, first real
        test): the screen went black ~0.9 s. Kernel log: "fbcon: Taking
        over console" 135 ms after the greeter quit, from
        pangolin-session's tty clear (fbcon defers taking the screen until
        text is written); also, when the last process closes a DRM card
        node, drm_lastclose() puts fbdev's (black) framebuffer up. Fixed in
        1.1.0-10: nothing writes to the VT after the greeter (pangolin-
        session skips its clear with PANGOLIN_FROM_GREETER, pangolin-greeter
        has none), pangolin-greeter-init keeps /dev/dri/card* open 10 s
        past river (opened while river is master, real displays only), and
        river's modeset frame already shows the splash (it was black for
        one frame). wlroots leaves the CRTC on with drmModeCloseFB, so the
        greeter's last frame stays until the desktop's first. [ ] Verify on
        the machine (i915 may still do a full modeset, MST connector).
      - Lag (user, 2026-10-19: "very laggy, especially text fields"):
        every keystroke and cursor blink redrew the whole screen (5120x2880
        at 4K 1.5): the embedder counted all Flutter drew as changed. The
        engine now hands the embedder its layer-tree diff (FrameDamage)
        with each frame (FlutterBackingStorePresentInfo.frame_damage), and
        LoginField and LoginShelf are repaint boundaries (the shelf's text
        never compares equal once re-recorded). Typing: 286x37 repainted
        instead of 2560x1440; a cursor blink 2x24. Same for the lock screen
        and every app.
      - Fixed: nothing typed reached the field until it was clicked: the
        first frame lays out at GTK's 200x200 default, LoginFitHeight
        switched widget structure when the window grew, the field was
        rebuilt and lost its text input (structure now fixed). Also the
        session's Flutter views are now their window's GTK focus widget
        (keys before any click: greeter, search opened with Super+S).
      Old problems:
      - Login doesn't transition smoothly to the desktop: there is still a
        flash of the console, and the desktop loads in a very janky way.
      - Wallpaper handling is very buggy.
      - It looks bad. Target: a Chromium OS-like login screen (large user
        avatars on a blurred wallpaper, a single pill password field,
        shelf-style bottom bar with power, network and accessibility),
        in the dahliaOS look.
      Hand-over to plan for: greeter and session on one continuous
      wallpaper (no VT switch shown, no black frame), the session's first
      frame ready before the greeter goes away.
- [ ] 1.7 Shell load time (user, 2026-10-18): reduce how long the shell
      takes to come up after login (measure: river start, engine start,
      services, first frame; then defer or parallelize what isn't needed
      for the first frame).
- [~] 1.8 Lock screen rewrite: done 2026-10-19 with the greeter's kit (no
      big clock, the time is in the shelf; Power menu: suspend, restart,
      shut down), [ ] real-hardware test. The five-attempts bug was
      pam_unix's unix_chkpwd helper losing its exit status to the Dart
      VM, which reaps child processes ("waitpid returned -1: No child
      processes" in the user's journal, audit res=success for the right
      password): the check now runs in a child process (`pangolin
      --check-password`, session/native/check_password.cc). Escape closes
      the open power menu instead of clearing the field.
      Original report (user, 2026-10-18): as janky as the
      greeter. Bug: the user had to type their correct password five times
      before it was accepted. Find the cause before redesigning:
      - Are keystrokes lost while the lock surface gets keyboard focus?
      - Is the field cleared during PAM's fail delay?
      - Is a PAM conversation still running from the previous try?
      - Does pam_faillock count those tries?
      Code: `lib/components/lock/`, `lib/services/session_lock.dart`,
      `lib/services/pam.dart`, `session/pam/pangolin`,
      `session/native/session_lock.cc`. Design it with 1.6 (same look:
      Chromium OS-like pill password field on the blurred wallpaper), with a
      smooth lock and unlock.
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
- [~] 2.5 The laptop panel turns back on when the only monitor in use is
      unplugged (user, 2026-10-19): pangolin-displays never leaves every
      output off, it turns on the built-in panel (eDP/LVDS/DSI, else the
      first monitor) at its preferred mode and a density scale
      (DisplayConfigurator.ensureOneEnabled). Headless: both outputs off,
      one comes back and the shell moves to it. [ ] Real unplug.
- [x] 2.6 Settings keeps ~/.config/monitors.xml up to date (user,
      2026-10-19: familiar in any desktop; GDM reads it from /etc/xdg).
      MonitorsXml.save writes GNOME's format for the connected monitors,
      vendor/product/serial from the EDID in sysfs as mutter derives them
      (checked against the user's file: GSM / LG ULTRAGEAR+ /
      510RMEN8E292), replacing only the configuration of the same monitors
      and keeping the others byte for byte; a non-version-2 file is left
      alone. Self-check: packages/display_config/test/monitors_xml_check.dart.
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
- [x] 2.7 Settings > Displays arrangement (user, 2026-10-24, first session
      on the 1.1.0-12 RPM): DP-8 and eDP-1 drawn overlapping, and nothing
      could be moved (the miniature only drew river's positions; nothing
      changed x/y). Now:
      - display_config's `settle` (src/layout.dart): no overlaps, no gaps,
        every display sharing an edge with another, top left at 0, 0;
        exact copies (same position and size) stay mirrors. Logical sizes
        truncate like wlroots (2560x1600 at 1.5 is 1706x1066).
      - DisplayConfigurator settles every layout before applying it and
        before comparing it with river's (otherwise an overlapping saved
        layout would be re-applied on every change). Overlaps could come
        from a monitors.xml in physical pixels (positions divided by each
        monitor's own scale, so mixed scales drift) or a profile saved at
        other scales.
      - The miniature shows the pending layout, settled as soon as the page
        opens (an overlap shows fixed, Apply ready). Displays can be
        dragged; a dropped one snaps against the others and lines up with
        an edge or centre within 10 screen pixels. Resolution, scale,
        rotation and on/off re-settle it.
      Self-check: packages/display_config/test/layout_check.dart. Verified
      headless against a two-output sway with the reported overlap: fixed on
      load, drag to the right, Apply (sway: 2275x1422+2560+0), Keep; and
      pangolin-displays settling an overlapping saved profile once, then
      leaving it. [ ] On the machine (MST DP-8 + eDP-1).
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
      2026-10-19 log (1.1.0-9, 4K@165 on DP-8, an MST connector: it comes
      back as DP-8 or DP-9 with "Bad link detected" on replug): 20 single
      refusals (one retry each) and 13 bursts of 20-200 ms where the kernel
      refused every frame, even 44-600 ms after river's last commit, so the
      busy commit isn't river's: most likely i915 retraining the link (a
      blocking internal modeset). Nothing to do in river; a different
      cable or port is the thing to try if freezes show.

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

- [ ] 3.4 **HIGHEST URGENCY.** 4K jitter (reported 2026-10-17): Pangolin at 4K is jittery where
      GNOME at the same resolution and refresh rate is smooth; lower
      resolutions are flawless. Earlier measurements (above) show the
      Flutter side is cheap at 4K, so the cost is in compositing, which
      grows with pixel count. Bring over mutter's techniques:
      - [ ] Measure first, on the 4K screen: river's render time per frame
        (PANGOLIN_PROFILE=frames logs it) and what gets damaged
        (WLR_SCENE_DEBUG_DAMAGE=highlight). Headless 720p: a shell frame
        (the clock ticks every second) costs river 3.3 ms of rendering
        against 0.1 ms for an idle frame, which is about 9x the pixels at 4K.
      - [ ] Only redraw what changed (mutter clips every redraw to the
        damaged region and uses buffer age). Check that the shell's
        commits carry real damage and not the whole 4K surface; a clock
        tick must not re-composite the screen.
      - [ ] Cache blur (GNOME Shell's blur effect re-renders only when what
        is behind it changes; GNOME doesn't blur live behind windows at
        all). Blur.zig re-blurs every region on every frame: keep each
        region's result and redo it only when damage hits its read area;
        downsample more at 4K.
      - [ ] Occlusion culling with opaque regions (mutter skips anything
        hidden behind opaque windows; wlroots' scene does too, but only
        for surfaces that declare an opaque region). The wallpaper, the
        shell and dahlia apps declare none, so everything below them is
        still drawn: declare opaque regions (wallpaper fully; app windows
        where they aren't translucent, e.g. inactive opaque windows).
      - [ ] Direct scanout for fullscreen windows (mutter "unredirects":
        a fullscreen game or video goes straight to the screen with no
        compositing). The shell is one full-screen transparent surface on
        the TOP layer above every window, which rules that out and adds a
        full-screen blend: give the shell surfaces sized to their content
        (taskbar strip, popups), or unmap it over fullscreen windows.
      - [ ] Frame scheduling: mutter measures its render time and starts
        compositing just before the deadline (dynamic max render time),
        does atomic commits on a separate high-priority KMS thread, and
        since GNOME 48 uses dynamic triple buffering. When a frame runs
        late it keeps one more in flight instead of missing a vblank, and
        the Intel GPU stays clocked up instead of idling between frames
        and downclocking. River renders double buffered right after
        vblank: a frame that runs past the 6 ms budget at 165 Hz misses
        the vblank (judder).
      - [ ] Render on the GPU that drives the screen. With two GPUs,
        wlroots renders on its primary one and copies every frame to an
        output on the other GPU (a 4K copy per frame at 165 Hz); mutter
        picks its render GPU and copy path per output. The user's 4K
        screen is on the Intel iGPU and the panel on NVIDIA: check which
        GPU river renders with, and have the session pick the GPU of the
        connected screen (WLR_DRM_DEVICES order). GNOME on that machine
        renders on card1 ("Boot VGA GPU /dev/dri/card1 selected as
        primary", the Intel GPU driving the 4K screen). River doesn't log
        its choice in the real session (nothing in the journal): log it.
      - User's nvtop comparison (2026-10-17): the Intel iGPU is much busier
        under Pangolin than under GNOME for the same workload. River does
        render on the iGPU, so the extra cost is river's own compositing
        work (redraw area, blur, no culling, no scanout); a cross-GPU copy
        is not the cause: the NVIDIA card stayed idle the whole time
        (user, 2026-10-17). Drop the GPU-choice item down.
      - User test (2026-10-17): turning blur off changes nothing, so blur
        isn't the main cost. The overview animation stutters at 4K, but
        not on GNOME. Per-pixel suspects that remain: during the overview
        two full-screen 4K Flutter surfaces repaint every frame (the shell
        overlay on TOP and the backdrop on the BACKGROUND desktop surface),
        each one is rendered by Flutter, copied again by the GTK embedder,
        then blended by river over the whole screen. GNOME draws its
        overview inside the compositor with a cached backdrop. Start here:
        measure an overview open at 4K (Flutter raster per view, river
        render time per frame), then make the backdrop static or drawn by
        river, and shrink and damage-limit the shell surfaces. Separate
        from resolution: Flutter paces at 60 Hz on a 165 Hz screen (uneven
        2-3 vblank steps); the engine patch fixes that later.
      - Measured 2026-10-18 (headless on the same Intel RPL-P iGPU,
        3840x2160 at 1.5 vs 1280x720, 60 Hz only: headless refuses other
        rates). River now logs GPU time per frame (wlroots scene timers,
        read 3 frames later) and what it draws (buffers, full-screen ones,
        opaque ones, area) with PANGOLIN_PROFILE=frames.
        - Overview at 4K: river 6-15 ms of GPU per frame, from three
          full-screen layers blended every frame (desktop, river's
          crossfade copy of it, the shell); none is marked opaque. Shell
          frames take 10-70 ms in total (raster 0.4 ms) against 2-3 ms at
          720p, and drop frames (gaps of 66-116 ms) at each open/close.
        - Effects off: same cost (blur isn't it, as the user found).
        - Window drag: river 2.3 ms GPU at 4K, 1.6 ms at 720p; the shell
          draws 3 frames during a drag (lazy views work). Same pacing at
          both sizes, so the headless drag doesn't show the 4K problem.
        - Real session log (/var/log/Pangolin.log, 2026-10-17): river
          renders on the Intel GPU (card1 primary; NVIDIA only gets the
          multi-GPU renderer). 1,093 i915 EBUSY refusals and 21 window
          manager timeouts (a client not answering a resize in 100 ms,
          river holds frames meanwhile) in ~3 h.
        - Open question for the user: was the lower resolution that runs
          flawlessly at 60 Hz? Flutter (shell and apps) draws at 60 fps;
          on 165 Hz that's uneven pacing whatever the resolution.
        - User: still jittery at 4K@60, while 1080p@144 is buttery smooth,
          so it's per-pixel cost, not 60 fps content on a 165 Hz screen.
        - Tried: desktop surface opaque once the wallpaper is drawn
          (gdk_window_set_opaque_region, re-applied after GTK's size
          allocations). A/B over 4 runs: no measurable gain (GPU timer
          noise from the shell sharing the GPU), so reverted.
        - 1.1.0-2 (fc45) carries the profiling: user to run one session
          with PANGOLIN_PROFILE=frames in ~/.config/pangolin/session.env
          (read by pangolin-session), then read /var/log/Pangolin.log.
        - Real 4K@165 profile (2026-10-18, 1.1.0-2): river's GPU time is
          low (median 0.4 ms) and it holds 165 Hz while the shell is
          idle, but every shell frame costs it a full-screen re-composite
          (the shell surface commits with whole-surface damage): 7.7 ms
          avg (p90 13.6) right after each clock tick against 1.2 ms
          otherwise. So a hitch every second during any motion, and 15-90%
          missed refreshes while the shell animates (popups, overview).
          The shell itself keeps 60 fps (5.8 ms median).
        - [x] Fix 1: the shell surface is a strip along the bottom (taskbar
          + 48 px for its tooltips) unless an overlay, a menu, a
          notification, the volume popup, the snap preview or the window
          switcher is on screen (lib/services/shell_area.dart, runner
          setShellHeight). Overlays and shell menus wait until it covers
          the screen (ensureFull) so they're laid out for it. Hot corners
          moved to river: reaching or leaving an output corner starts a
          manage sequence (Cursor.updateCorner), the window manager
          checks the pointer position (river.dart _checkHotCorner).
          Headless 4K A/B: river GPU after a clock tick 4.5-6.8 ms avg
          (max 12.9) before, 0.3-1.3 ms after; one full-screen buffer
          (the wallpaper) instead of two while idle. Verified: overview
          by the hot corner, launcher, taskbar tooltip, taskbar menu,
          toast. Untested on the real 4K screen yet (1.1.0-3).
        - 1.1.0-3 on the real screen: windows no longer lag when moving;
          popups and the overview still feel the same. Regression: the
          taskbar flashed at the top whenever the surface grew (overview,
          snap preview, screenshot, search, QS, notifications). Cause:
          river moved the layer surface to its new box at configure time,
          so the old strip buffer showed at the top until the client drew
          the full size. Fixed (1.1.0-4): a mapped layer surface keeps its
          position until it shows the configured size
          (LayerShellOutput.sendConfigures / LayerSurface.deferred).
          Region burst captures: old river shows it, new river clean in
          5 of 5 runs.
        - [x] Patched Flutter Linux embedder (2026-10-18, moved up from the
          end of the list by the user; third_party/flutter_engine, rebuilt
          by tool/build_engine.sh, swapped into release bundles by
          tool/build.sh when the SDK's engine version matches):
          - Frame pacing: a vsync callback on a grid of the fastest
            display's refresh interval (stock: fixed 60 Hz).
            FLUTTER_LINUX_FPS=N / unlimited (e.g. in
            ~/.config/pangolin/session.env). Headless: 60, 120, ~273 fps.
          - Damage: what a frame drew (the engine's layer paint regions)
            or the previous one did is what changed; GTK repaints only
            that (gtk_widget_queue_draw_region, buffer age keeps older
            buffers right) and, for views that are their whole surface
            (Pangolin's desktop and shell), Mesa's whole-surface damage
            (GTK 3 binds wl_compositor v3, no damage_buffer) is replaced
            by it in our wl_proxy_marshal_flags (fl_pangolin_damage.cc).
            Shell taskbar commits now damage (0, 672, 1280, 48) instead of
            the whole surface. 4K app menu A/B: river GPU median 5.4 ->
            2.1 ms, avg 7.0 -> 4.6 ms. No stale pixels after scrolling.
          - Overview unchanged (river's own full-screen crossfade copy and
            moving mirrors damage everything): next, a cheaper backdrop
            transition (a dim rect instead of a full-screen texture copy).
          - App menu opening: bursts of 15-34 ms frames (first-frame icon
            decoding / shader work competing with river's part animation).
        - Noticed: Atk-CRITICAL "atk_socket_embed: plug_id != NULL" at shell
          start (stock embedder too).
        - [x] Escape doesn't close the app menu (old builds too): fixed
          2026-10-19, Escape closes any open shell overlay (ShellState).
        - Candidates after that data: overview labels static during the
          transition (no 4K shell redraw per frame); shell surface shrunk
          to the taskbar strip when nothing else is open (needs river-side
          hot corners: today they're spots on the full-screen shell
          surface, and pointer_position only comes with manage sequences);
          skip zero-opacity buffers.
        - [x] Overview, 1.1.0-6 (2026-10-18). Benchmarks run with six apps
          open (user: overview benchmarks need several windows;
          test-harness/bench/perf6.sh, anim.py counts late frames inside
          animations only, since app redraws at idle aren't jank).
          - No crossfade copy: river tints the window area and the desk
            strip (river-blur-v1 v4 set_tint), and river clips the shell
            to the taskbar strip while it animates (set_visible_area,
            ShellSurfaceArea.quiet, now held until the close is done).
            wlroots draws opacity-0 buffers, so hidden copies cost too.
          - Windows stay activated while the shell has keyboard focus
            (Seat.window_before_layer): apps don't redraw on the overview.
          - River draws the wallpaper (PANGOLIN_WALLPAPER=1, Splash.zig
            keeps the splash, reloads it via inotify, XRGB, written at the
            output's width by SplashCache); the desktop surface is
            transparent and clipped to 1x1, or to the desk bar while the
            overview is open.
          - Desk thumbnails from a 480 px decode (the 4K wallpaper was
            decoded and uploaded on every opening: a 50 ms frame).
          - Embedder: GDK 3's gdk_cairo_draw_from_gl uploads the window's
            (empty) cairo surface on the CPU under any alpha texture, for
            the whole painted area (59 MB, ~20-25 ms of main thread at 5K;
            found with a main-thread stack sampler). skip_surface_upload
            marks the area GL-drawn with a blit of a 1x1 RGB renderbuffer,
            clears it and blends the frame. If GDK can't blit (GLES without
            ANGLE, groups), its software fallback flips cr without
            restoring it (apps came out upside down): detected, undone,
            and that view falls back to the old path.
          - Six-app A/B, old vs new embedder, 3 runs each: late frames
            inside animations 19% vs 12% average; shell UI-thread stalls
            over 8 ms 10-20 vs 3-7 per run.
          - 1.1.0-7: regressions from the clips fixed. wlroots moves a
            clipped surface's buffer node to the clip's corner, so Blur.zig
            now takes the surface origin from the clip (surfaceOrigin): the
            taskbar's blur was below the screen. The scene also drops
            buffers it doesn't own once uploaded, so the blur walk takes
            texture-only buffers too: it didn't see river's wallpaper. A
            clipped layer surface still takes input over its whole box
            through an empty scene buffer (LayerSurface.input_proxy, its
            point_accepts_input defers to the surface's input region);
            right-clicking the desktop did nothing before.
          - 1.1.0-8 (2026-10-19): no full repaints of the shell left after
            startup (each was 10-25 ms of the main thread at 4K, plus a
            full composite). Found by logging what GTK repaints
            (PANGOLIN_PROFILE=frames, "Pangolin: repaint"). Sources:
            - river_blur.cc queued a whole-window redraw for every
              blur-region update (the taskbar's, on each clock tick and
              animation): now unchanged regions are skipped and a 1 px
              redraw makes the commit.
            - gtk-layer-shell commits a keyboard-mode change by
              invalidating the whole window: the runner interposes
              gdk_window_invalidate_rect around it (1 px instead).
            - Embedder: GtkWidget's default focus-out redraws the whole
              view (FlView only overrode focus-in); and a second redraw
              of a frame took "no damage left" for "unknown" (full).
            Six-app overview: late frames in animations 0-8% (was 6-9%).
          - Window drags (user: stutters build up): river queues input while
            a manage sequence waits for the window manager, and a drag makes
            every motion one. A fast mouse outran it: the window lagged
            further and further and the queue overflowed (402 "dropping
            pointer_motion_relative" errors in the user's log). Queued
            motion is now coalesced (Seat.coalesceMotion). Headless 1 kHz
            drag: no drops, no backlog. Real GPU time per drag frame is
            1-1.4 ms at 4K@165 (headless overstates it ~4x).
          - Frame pacing at 165 Hz (2026-10-19, the user's log): in
            overview animations the shell drew every other refresh (12.1 ms
            apart) with 3 ms builds. Flutter now runs Dart on the GTK
            thread by default, and that thread's task runner wakes with
            g_timeout_add (whole ms): every frame started 1.7 ms late (p50).
            The shell and dahlia_apps now set
            FL_UI_THREAD_POLICY_RUN_ON_SEPARATE_THREAD (no FFI into GTK
            anywhere); the embedder answers vsync on that thread and, when a
            frame ran past the next tick, starts the next one right away
            instead of a refresh later. Headless overview with
            FLUTTER_LINUX_FPS=165 (bench/cadence.py): skipped frames
            0.5-0.7% (was 2.2-4.2%), start delay 0.04 ms (was 1.7).
          - [ ] Left: one full shell repaint at the start of a close, most
            likely the keyboard focus change (GTK state flags). It still
            costs a 59 MB cairo surface clear and free, ~25 ms in bad
            runs, and river then drops to 30 fps for a few frames. Find
            the trigger, avoid the repaint. Also: the first details frame
            (labels) rasters in ~18 ms.

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
- [x] 4.6 Activity Monitor: Settings-style sidebar, Run task (Ctrl+R, in
      terminal option), field styling/alignment, polling off the UI thread.
      Done 2026-10-24, verified headless (Flutter 3.47.7, the engine of
      third_party/flutter_engine; stock embedder, Xvfb/X11 in a Debian
      container, so river's blur behind the rail is untested):
      - Settings' rail moved to the kit (kit/rail.dart: DahliaRail,
        RailItem, RailIcon); Settings and Activity Monitor both use it.
        Pages: Processes, then CPU, Memory, Network, Disk, each with its
        chart (legend, tabular figures) and a details group.
      - Polling: ProcFs.poll reads /proc on a background isolate
        (Isolate.run), one poll at a time, rescheduled after each one; the
        process walk only runs while Processes shows (per-process CPU is
        then averaged since the last walk). Load average and uptime come
        with the sample; regexes are compiled once.
      - Run Task (button and Ctrl+R): runs the command with $SHELL -c,
        detached, or in Terminal (`terminal -e $SHELL -c …`, the tab stays
        open). A plain program name not in $PATH is refused with an error.
        Found in testing and fixed: Enter unfocused the field (onSubmitted),
        so a retry after an error couldn't be typed; clicking the switch
        took focus from the field; Ctrl+R died after a click on empty space
        (focus fell back to the route's scope, above the shortcuts: the
        page is now its own FocusScope); the switch's off track was the
        dialog's color (now on a section fill).
      - Table: the header and rows share one column layout (fixed numeric
        columns, sort arrow before right-aligned labels), one text size,
        tabular figures, no divider, inside a section; rounded selection;
        the "My processes" filter is a filled pill like the search field.
        Names cut to the kernel's 15 characters ("xdg-desktop-por") take
        the full name from argv[0].
      - kit InfoRow: the value is Expanded (was a loose Flexible, so it sat
        a third of the way across despite TextAlign.end); every details
        list, Settings > About included, now ends at the right edge.
      Verified: all five pages, search, the unknown-program
      error and retry, a detached `sleep` showing in /proc, a command run
      in Terminal (output and "[Process exited with code 0]"), Settings'
      rail, search and page switching.
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
- [x] 6.2 Accent from the wallpaper; custom accent picker (2026-10-17).
      - "From wallpaper" swatch: setting accent_from_wallpaper. The shell's
        WallpaperAccent (lib/services/wallpaper_accent.dart) takes the hue
        covering the most vivid area of the wallpaper (64 px sample, kept
        readable) on every wallpaper change; unit tests in
        test/wallpaper_accent_test.dart.
      - "Custom" swatch: hue/saturation/brightness picker with hex field,
        stored as a hex ColorResource.
      Headless: a photo wallpaper gave #997b4d and the UI followed; the picker
      opens with the current color.
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
- [x] 6.6 Window borders, macOS Sequoia-like (user request 2026-10-17):
      a 1 px hairline, white 16% in dark mode and black 12% in light.
      Optional: "Window borders" in Settings > Appearance (window_borders,
      on by default).
      - dahliaOS apps: GTK CSS ring in apps/linux/runner (setBorder on the
        window channel, sent by kit/app.dart).
      - Pangolin-decorated windows: river cutouts take a trailing
        color/width and draw the edges and arcs (Blur.zig).
      Also: GTK rounded dahliaOS windows with its theme's 8 px; now 12 px,
      as before and as the title bars. Headless: ring present and gone when
      off, radius 12. River path verified with an SSD test window: edges
      and corner arcs 12% darker in light mode.
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
- [~] 7.5 Shell settings (2026-10-17). Taskbar left/right/top positions
      come later (decided 2026-10-16).
      - [x] Taskbar size Small/Medium/Large (40/48/56 px, the bar scaled
        as a whole; taskbar_size). Work area, maximized and snapped
        windows follow live (river _refitToWorkArea), overlays sit above
        it. Verified headless.
      - [~] Hide automatically (taskbar_autohide): windows get the whole
        screen, a 2 px strip at the bottom edge brings the bar back, it
        stays out while hovered or while an overlay/menu is open. Verified
        headless, but: after the slide away the top ~10 px of the bar can
        stay on screen (stale pixels in the shell's own buffer, still
        there with river re-rendering everything; engine renders full
        frames). Next: find which frame GTK/FlView last presented.
      - [x] App menu: Full screen (grid over the screen; also a button in
        the menu, which replaces the dead edit button; launcher_fullscreen)
        and Sort apps A to Z / Category (freedesktop main categories,
        test/launcher_sections_test.dart; launcher_sort).
      - [x] Profile picture: the Flutter logo placeholder is now the
        user's initial (shared UserAvatar, as on the login screen) and
        opens the account menu; the menu shows the full name.
- [ ] 7.6 QS accounts: list sessions; Switch Account only to sessions
      already running (loginctl activate). greetd can't start a second
      login (decided 2026-10-16).
- [x] 7.7 Bluetooth in Quick Settings, done 2026-10-17.
      - Found: the Bluetooth tile only flipped a preference
        (enableBluetooth); nothing applied it to BlueZ.
      - lib/services/bluetooth.dart: BlueZ over the system bus via the
        object manager: adapter power, devices, battery; connect,
        disconnect, pair + trust; scans only while a page shows devices.
      - Tile: real power state, connected device as the subtitle, chevron to
        pages/qs_bluetooth_page.dart (devices, Settings link, "Turn on",
        no-adapter state).
      - Taskbar icon follows the adapter.
      Verified headless against a fake BlueZ on a private system bus
      (scratchpad fakebluez + bt-up.sh): connect, pair + connect,
      disconnect, scan start/stop, tile subtitle. [ ] Real adapter; pairing
      that needs a PIN (BlueZ agent) isn't handled.
- [x] 7.8 Wi-Fi and Airplane mode tiles are fake too (found 2026-10-17): they
      flipped preferences (enableWifi, enableAirplaneMode) that nothing
      applied, and the network page was legacy synchronous nmcli, list only.
      - lib/services/wifi.dart: NetworkManager over D-Bus. WirelessEnabled;
        networks one per SSID (strongest AP); saved connections; connect
        (ActivateConnection for saved, AddAndActivateConnection otherwise
        with wpa-psk/sae; the password comes from VpnService's secret agent
        and NetworkSecretOverlay); disconnect; scan.
      - AirplaneMode turns Wi-Fi and Bluetooth off and restores them.
      - Rewritten pages/qs_network_page.dart; lib/services/network_manager.dart
        removed.
      Verified headless against a fake NetworkManager (test-harness
      fakesys/fakenm.dart): join open, join WPA (key-mgmt sent), disconnect,
      Wi-Fi off, airplane on/off. [ ] Real NM; password prompt end to end;
      enterprise networks go to Settings.

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
- [x] 8.6 Lock screen animates back to the desktop: on unlock river keeps
      each output's last lock frame above everything and fades it out over
      350 ms (LockManager.zig startFade/beforeFrame). Verified headless with
      an ext-session-lock test client: the lock color fades into the desktop
      over four frames, then the desktop alone.
- [ ] 8.9 Adaptive snapping and tiling like Windows 11 (requested
      2026-10-17). Today (lib/services/wm/river.dart): halves and maximize
      only (`_Snap { left, right, maximized }`), by dragging to the screen
      edges or with Super+arrows, with a snap preview. To add:
      - more zones: quarters (corners), and thirds on wide screens (the
        "adaptive" part: layouts chosen by screen width and aspect, e.g.
        3-column on ultrawide, top/bottom halves on portrait);
      - snap layouts: a flyout of layouts when hovering the maximize
        button (and Super+Z), pick a zone to place the window;
      - snap assist: after snapping one window, offer the other windows
        as thumbnails to fill the remaining zones;
      - shared edges: dragging the edge between snapped windows resizes
        them together;
      - snap groups: windows snapped together come back together (taskbar
        hover, Alt+Tab), and dragging one out restores its floating size;
      - keyboard: Super+arrows walk through zones (half → quarter),
        Super+Up/Down maximize and restore;
      - setting to turn snap layouts and snap assist off.
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
