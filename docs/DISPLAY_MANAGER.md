# pangolin-dm: Pangolin's display manager

Pangolin's own display manager (roadmap 1.9), built with GDM's
architecture and without greetd, so the login screen can hand over to the
desktop without a black frame or a console flash. C, with only libc and
libpam (`dm/`).

## Processes

| GDM | pangolin-dm | Runs as | Does |
| --- | --- | --- | --- |
| `gdm` | `pangolin-dm` (`dm/src/daemon.c`) | root, `pangolin-dm.service` | Owns the VT, keeps the greeter running, answers it on a socket, starts a worker per login |
| `gdm-session-worker` | `pangolin-dm --worker` (`dm/src/worker.c`) | root, one per login | Holds the PAM handle: the conversation, opening the session, running it as the user, closing it |
| `gdm-launch-environment` + gnome-shell | the greeter worker + `pangolin-greeter` | `pangolin-greeter`, session class `greeter` | river and the shell in greeter mode (`lib/components/greeter`) |

Neither the daemon's main process nor the greeter ever has a PAM handle:
the greeter only relays questions and answers, as GDM's does.

PAM services: `pangolin-dm` for password logins (as `gdm-password`: on
Fedora through `password-auth`, which brings `pam_systemd`,
`pam_systemd_home` and `pam_unix`) and `pangolin-dm-greeter` for the login
screen's own session (as `gdm-launch-environment`). `packaging/rpm/*.pam`;
`tool/install.sh` writes Debian-style ones where there is `common-auth`.

## A login

1. The daemon starts at boot after Plymouth quits keeping its last frame
   (the greeter package's `plymouth-quit` drop-in: `--retain-splash`),
   activates VT 1 and starts the greeter: a worker in greeter mode opens a
   session for `pangolin-greeter` (class `greeter`, seat0, VT 1; logind
   registers it through `pam_systemd`) and runs `pangolin-greeter` in it
   with `PANGOLIN_DM_SOCK` set.
2. The greeter connects. Only the greeter user's connections are accepted
   (`SO_PEERCRED`; the socket is that user's, mode 0600, in
   `/run/pangolin-dm`).
3. `begin user` starts a user worker, which runs `pam_authenticate`. Each
   PAM message comes to the greeter as the reply to its request: a
   `question` (answered with `answer text`) or a `message` (acknowledged
   with `answer`). A wrong password ends the worker (`failed reason=auth`);
   the greeter begins again. An expired password is changed right there
   (`pam_chauthtok`, more questions).
4. `verified`: the greeter sends `start session=<id>`. The worker reads
   that session's command from `wayland-sessions/<id>.desktop` itself (the
   greeter never gives a command line) and replies `ready`; the greeter
   gets `started`, fades out and exits (made to after 10 seconds).
5. Once the greeter's session is closed and logind has let go of the VT,
   the daemon tells the worker `run`. logind keeps a session that has
   ended, and its VT, until every process in it is gone, and refuses a
   new session on that VT meanwhile (`VirtualTerminalAlreadyTaken`: river
   then times out waiting for its session to become active). So the
   greeter's worker ends what the greeter left in its session scope
   (SIGTERM, then SIGKILL after a second), and the daemon waits until no
   session file in `/run/systemd/sessions` has the VT; after 5 seconds it
   moves to a free VT (`VT_OPENQRY`), as GDM's sessions run on their own.
   The greeter comes back after a session the same way. So that the
   kernel doesn't show its console once the greeter's river has closed
   the display devices, the daemon opens them at `ready` (while that river
   still has them, so it doesn't become their master) and closes them 10
   seconds after `run`. The worker sets `XDG_SESSION_TYPE`, `XDG_SESSION_CLASS`,
   `XDG_SESSION_DESKTOP`, `XDG_SEAT` and `XDG_VTNR` for `pam_systemd`,
   `pam_setcred` and `pam_open_session` (logind registers the session, a
   systemd-homed home is unlocked), then starts the session as the user
   through a login shell (`sh -l -c 'exec "$@"'`, as GDM does), with
   nothing connected to the VT (text on it would show the console).
6. When the session ends, the worker closes the PAM session (the homed home
   is locked again) and exits; the daemon starts the greeter again.

The greeter can hand the session only `PANGOLIN_FROM_GREETER` and the
language variables (`dm_greeter_env_allowed`); the daemon also sets
`XDG_CURRENT_DESKTOP` from the desktop file's `DesktopNames`.

## The greeter's protocol

A frame is a 32 bit little endian length, then that many bytes of
`key NUL value NUL` pairs, `type` first. Keys may repeat (`env`). One reply
per request. The same framing goes between the daemon and its workers.

| Request | Fields | Replies |
| --- | --- | --- |
| `begin` | `user`, `service` (`password`) | `question`, `message`, `verified`, `failed` |
| `answer` | `text` (none to acknowledge a message) | the same |
| `start` | `session` (desktop file id), `env` (repeated) | `started`, `error` |
| `cancel` | | `ok` |

| Reply | Fields |
| --- | --- |
| `question` | `text`, `secret` (`1`: hide what's typed) |
| `message` | `text`, `kind` (`info` or `problem`) |
| `verified` | |
| `failed` | `reason` (`auth`, `account`, `cancelled`, `error`), `text` |
| `started`, `ok` | |
| `error` | `text` |

The greeter side is `lib/services/display_manager.dart` (`PangolinDm`,
behind `LoginBackend`, which also still speaks greetd's protocol).

## Testing

`dm/tests/run.sh` runs everything as any user, without root or a VT: the
daemon with `--test --once`, PAM services from a scratch folder
(`--pam-confdir`) whose `auth` is a test module (`pam_pangolin_test.c`: a
message, then a password question, only `secret123` passes), a scripted
greeter (`greeter.py`) and a test session that writes down its arguments
and environment. It checks the conversation (message, question, a wrong
then the right password), a session name with a path in it refused, and
what the session got (`XDG_*`, `DesktopNames`, the allowed variable but not
`LD_PRELOAD`). `test/display_manager_test.dart` covers the greeter's client.

Trying it on a machine: install the greeter package, then from a text
console (Ctrl+Alt+F3) so there is a way back:

    sudo systemctl disable gdm
    sudo systemctl enable pangolin-dm
    sudo reboot

Back to GDM: `sudo systemctl disable pangolin-dm && sudo systemctl enable gdm`.
The daemon logs to the journal: `journalctl -b -u pangolin-dm`.
Frame timings of the login screen (river's frames, the shell's slow frames
and manage sequences) go to `/var/log/PangolinGreeter.log` with
`PANGOLIN_PROFILE=1` in the daemon's environment, which it passes on to the
greeter (`sudo systemctl edit pangolin-dm`, then under `[Service]`:
`Environment=PANGOLIN_PROFILE=1`).

## Next

- The seamless hand-off: the session's river ready, its first frame drawn,
  before the greeter's goes, then DRM master passed over with no modeset
  when the mode stays the same (roadmap 1.9 has the options: the same VT,
  or logind's TakeDevice/PauseDevice).
- systemd-homed beyond PAM: unlocking after a suspend that locked the home
  (a greeter-side screen, as GNOME has). Homed users are in the user list
  (through NSS) with their avatars from homed's blob folders.
- More conversations next to the password one: fingerprint and smartcard
  (their own PAM services, run at the same time, as GDM's).
- Autologin and timed login, fast user switching, multi-seat (logind's
  seats), and greetd's support dropped once this has replaced it on the
  machine.
- Performance: measure greeter start and login to first frame, then
  preload what the session needs while the password is typed.
