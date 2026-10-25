/* Copyright 2026 The dahliaOS Authors
 * SPDX-License-Identifier: Apache-2.0 */

#ifndef PANGOLIN_DM_H
#define PANGOLIN_DM_H

#include <stddef.h>

/* A line in the log (stderr, which systemd sends to the journal). */
void dm_log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

/* A desktop session (wayland-sessions/<id>.desktop). */
struct dm_session {
	char *id;
	char *name;
	/* DesktopNames, ';' turned into ':' as XDG_CURRENT_DESKTOP wants. */
	char *desktop_names;
	/* Exec, split into arguments, NULL terminated. */
	char **argv;
};

/* Finds session [id] in the wayland-sessions folders under [dirs] (colon
 * separated data folders; NULL for /usr/local/share:/usr/share). 0, or -1
 * with the reason in [error]. */
int dm_session_find(const char *id, const char *dirs, struct dm_session *out, char *error, size_t error_len);
void dm_session_free(struct dm_session *s);
/* Splits a desktop file's Exec value; field codes (%f, %U...) dropped. */
char **dm_split_exec(const char *exec);

/* The variables a greeter may hand to the session it starts. */
int dm_greeter_env_allowed(const char *assignment);

int worker_main(void);
int daemon_main(int argc, char **argv);

#endif
