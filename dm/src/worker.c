/* Copyright 2026 The dahliaOS Authors
 * SPDX-License-Identifier: Apache-2.0
 *
 * The session worker (GDM's gdm-session-worker): one process per login, run
 * as root by the daemon (pangolin-dm --worker, descriptor 3 its end of a
 * socket pair). It holds the PAM handle, so neither the daemon's main
 * process nor the greeter ever does:
 *
 *   daemon -> hello (mode, service, user, tty, vt, seat, ...)
 *   user mode:  PAM conversation (question/message <-> answer), then
 *               verified or failed; start (a session) -> ready;
 *               run -> running ... ended
 *   greeter mode: opens the greeter's session (class greeter) at once and
 *               runs the greeter in it: running ... ended
 *
 * pam_systemd registers the session with logind (seat, VT, class), and with
 * systemd-homed's pam_systemd_home in the stack the user's home is unlocked
 * when the session opens and locked again when it closes. */

#define _GNU_SOURCE
#include "dm.h"
#include "pam.h"
#include "proto.h"

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static int daemon_fd = 3;

static void send_simple(const char *type, const char *key, const char *value)
{
	struct msg m;
	msg_init(&m, type);
	if (key) msg_add(&m, key, value);
	msg_send(daemon_fd, &m);
	msg_free(&m);
}

/* PAM's questions and messages go to the daemon, which shows them in the
 * greeter; each waits for its answer (an empty one for messages). */
static int converse(int n, const struct pam_message **msgs, struct pam_response **out, void *data)
{
	(void)data;
	if (n <= 0 || n > 32) return PAM_CONV_ERR;
	struct pam_response *resp = calloc((size_t)n, sizeof *resp);
	if (!resp) return PAM_BUF_ERR;
	for (int i = 0; i < n; i++) {
		struct msg q;
		int style = msgs[i]->msg_style;
		if (style == PAM_PROMPT_ECHO_OFF || style == PAM_PROMPT_ECHO_ON) {
			msg_init(&q, "question");
			msg_add(&q, "secret", style == PAM_PROMPT_ECHO_OFF ? "1" : "0");
		} else if (style == PAM_ERROR_MSG || style == PAM_TEXT_INFO) {
			msg_init(&q, "message");
			msg_add(&q, "kind", style == PAM_ERROR_MSG ? "problem" : "info");
		} else {
			goto fail;
		}
		msg_add(&q, "text", msgs[i]->msg);
		int sent = msg_send(daemon_fd, &q);
		msg_free(&q);
		if (sent < 0) goto fail;

		struct msg a;
		if (msg_recv(daemon_fd, &a) < 0) goto fail;
		if (strcmp(msg_type(&a), "answer") != 0) {
			msg_free(&a);
			goto fail;
		}
		if (style == PAM_PROMPT_ECHO_OFF || style == PAM_PROMPT_ECHO_ON) {
			const char *text = msg_get(&a, "text");
			resp[i].resp = strdup(text ? text : "");
		}
		msg_free(&a);
	}
	*out = resp;
	return PAM_SUCCESS;
fail:
	for (int i = 0; i < n; i++) {
		if (resp[i].resp) {
			explicit_bzero(resp[i].resp, strlen(resp[i].resp));
			free(resp[i].resp);
		}
	}
	free(resp);
	return PAM_CONV_ERR;
}

struct hello {
	struct msg m;
	const char *mode;
	const char *service;
	const char *user;
	const char *tty;
	const char *vt;
	const char *seat;
	const char *confdir;
	const char *sessions;
};

static pam_handle_t *start_pam(const struct hello *h, const struct pam_conv *conv)
{
	pam_handle_t *pamh = NULL;
	int rc = h->confdir && *h->confdir
		? pam_start_confdir(h->service, h->user, conv, h->confdir, &pamh)
		: pam_start(h->service, h->user, conv, &pamh);
	if (rc != PAM_SUCCESS) {
		dm_log("worker: pam_start(%s): %s", h->service, pam_strerror(pamh, rc));
		return NULL;
	}
	if (h->tty && *h->tty) pam_set_item(pamh, PAM_TTY, h->tty);
	return pamh;
}

static void put_env(pam_handle_t *pamh, const char *key, const char *value)
{
	if (!value || !*value) return;
	char buf[1024];
	snprintf(buf, sizeof buf, "%s=%s", key, value);
	pam_putenv(pamh, buf);
}

/* An environment for execve: PAM's (pam_env, pam_systemd's XDG_RUNTIME_DIR
 * and XDG_SESSION_ID...), the account's basics, then [extra]. */
static char **session_env(pam_handle_t *pamh, const struct passwd *pw, const char **extra, size_t n_extra)
{
	char **pamenv = pam_getenvlist(pamh);
	size_t n = 0;
	while (pamenv && pamenv[n]) n++;
	char **env = calloc(n + n_extra + 8, sizeof *env);
	size_t k = 0;
	for (size_t i = 0; i < n; i++) env[k++] = pamenv[i];
	free(pamenv);
	const char *defaults[][2] = {
		{"HOME", pw->pw_dir},
		{"SHELL", pw->pw_shell},
		{"USER", pw->pw_name},
		{"LOGNAME", pw->pw_name},
		{"PATH", "/usr/local/bin:/usr/bin:/bin"},
	};
	for (size_t d = 0; d < sizeof defaults / sizeof *defaults; d++) {
		size_t klen = strlen(defaults[d][0]);
		int have = 0;
		for (size_t i = 0; i < k; i++) {
			if (strncmp(env[i], defaults[d][0], klen) == 0 && env[i][klen] == '=') have = 1;
		}
		if (!have && asprintf(&env[k], "%s=%s", defaults[d][0], defaults[d][1]) >= 0) k++;
	}
	for (size_t i = 0; i < n_extra; i++) env[k++] = strdup(extra[i]);
	env[k] = NULL;
	return env;
}

/* Runs [argv] as [pw] in the open PAM session; reports running and ended.
 * Returns the session's exit status. */
static int run_session(pam_handle_t *pamh, const struct passwd *pw, char *const *argv, const char **extra, size_t n_extra, int login_shell)
{
	char **env = session_env(pamh, pw, extra, n_extra);
	pid_t pid = fork();
	if (pid < 0) {
		dm_log("worker: fork: %s", strerror(errno));
		return -1;
	}
	if (pid == 0) {
		setsid();
		signal(SIGPIPE, SIG_DFL);
		int null = open("/dev/null", O_RDWR);
		if (null >= 0) {
			/* Nothing goes to the VT: written text would make the kernel
			 * show the console between the greeter and the desktop. */
			dup2(null, 0);
			dup2(null, 1);
			dup2(null, 2);
			if (null > 2) close(null);
		}
		close(daemon_fd);
		if (geteuid() == 0) {
			if (initgroups(pw->pw_name, pw->pw_gid) < 0 || setgid(pw->pw_gid) < 0 || setuid(pw->pw_uid) < 0) _exit(126);
			if (setuid(0) == 0) _exit(126); /* must be unable to get root back */
		} else if (geteuid() != pw->pw_uid) {
			_exit(126);
		}
		if (chdir(pw->pw_dir) < 0 && chdir("/") < 0) _exit(126);
		if (login_shell) {
			/* As GDM does: a login shell first, so the profile
			 * (/etc/profile.d, ~/.profile) sets the session up. */
			size_t argc = 0;
			while (argv[argc]) argc++;
			char **shell_argv = calloc(argc + 6, sizeof *shell_argv);
			shell_argv[0] = "sh";
			shell_argv[1] = "-l";
			shell_argv[2] = "-c";
			shell_argv[3] = "exec \"$@\"";
			shell_argv[4] = "pangolin-dm-session";
			for (size_t i = 0; i < argc; i++) shell_argv[5 + i] = argv[i];
			execve("/bin/sh", shell_argv, env);
		} else {
			execvpe(argv[0], argv, env);
		}
		_exit(127);
	}
	struct msg m;
	msg_init(&m, "running");
	msg_add_int(&m, "pid", pid);
	msg_send(daemon_fd, &m);
	msg_free(&m);

	int status = 0;
	while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
	}
	int code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
	for (char **e = env; *e; e++) {
		explicit_bzero(*e, strlen(*e));
		free(*e);
	}
	free(env);
	return code;
}

static int open_session(pam_handle_t *pamh, const struct hello *h, const char *class, const char *desktop)
{
	put_env(pamh, "XDG_SESSION_TYPE", "wayland");
	put_env(pamh, "XDG_SESSION_CLASS", class);
	put_env(pamh, "XDG_SESSION_DESKTOP", desktop);
	put_env(pamh, "XDG_SEAT", h->seat);
	put_env(pamh, "XDG_VTNR", h->vt);
	int rc = pam_setcred(pamh, PAM_ESTABLISH_CRED);
	if (rc != PAM_SUCCESS) {
		dm_log("worker: pam_setcred: %s", pam_strerror(pamh, rc));
		return -1;
	}
	rc = pam_open_session(pamh, 0);
	if (rc != PAM_SUCCESS) {
		dm_log("worker: pam_open_session: %s", pam_strerror(pamh, rc));
		pam_setcred(pamh, PAM_DELETE_CRED);
		return -1;
	}
	return 0;
}

static void close_session(pam_handle_t *pamh)
{
	pam_close_session(pamh, 0);
	pam_setcred(pamh, PAM_DELETE_CRED);
}

/* The greeter's session: class greeter, the greeter user, no questions. */
static int greeter_worker(const struct hello *h)
{
	const char *args[64];
	size_t n_args = msg_get_all(&h->m, "arg", args, 63);
	const char *extra[64];
	size_t n_extra = msg_get_all(&h->m, "env", extra, 64);
	if (n_args == 0 || n_args > 63 || n_extra > 64) return 1;
	args[n_args] = NULL;

	struct passwd *pw = getpwnam(h->user);
	if (!pw) {
		dm_log("worker: no user %s for the greeter", h->user);
		send_simple("ended", "status", "-1");
		return 1;
	}
	struct pam_conv conv = {converse, NULL};
	pam_handle_t *pamh = start_pam(h, &conv);
	if (!pamh) {
		send_simple("ended", "status", "-1");
		return 1;
	}
	int rc = pam_acct_mgmt(pamh, 0);
	if (rc != PAM_SUCCESS || open_session(pamh, h, "greeter", "pangolin-greeter") < 0) {
		if (rc != PAM_SUCCESS) dm_log("worker: greeter account: %s", pam_strerror(pamh, rc));
		pam_end(pamh, rc);
		send_simple("ended", "status", "-1");
		return 1;
	}
	int code = run_session(pamh, pw, (char *const *)args, extra, n_extra, 0);
	close_session(pamh);
	pam_end(pamh, PAM_SUCCESS);
	struct msg m;
	msg_init(&m, "ended");
	msg_add_int(&m, "status", code);
	msg_send(daemon_fd, &m);
	msg_free(&m);
	return 0;
}

/* A login: authentication, then (once the daemon says) the user's session. */
static int user_worker(const struct hello *h)
{
	struct pam_conv conv = {converse, NULL};
	pam_handle_t *pamh = start_pam(h, &conv);
	if (!pamh) {
		send_simple("failed", "reason", "error");
		return 1;
	}
	int rc = pam_authenticate(pamh, 0);
	if (rc != PAM_SUCCESS) {
		struct msg m;
		msg_init(&m, "failed");
		msg_add(&m, "reason", rc == PAM_CONV_ERR || rc == PAM_ABORT ? "cancelled" : "auth");
		msg_add(&m, "text", pam_strerror(pamh, rc));
		msg_send(daemon_fd, &m);
		msg_free(&m);
		pam_end(pamh, rc);
		return 1;
	}
	rc = pam_acct_mgmt(pamh, 0);
	if (rc == PAM_NEW_AUTHTOK_REQD) {
		/* An expired password: PAM asks for a new one right here. */
		rc = pam_chauthtok(pamh, PAM_CHANGE_EXPIRED_AUTHTOK);
	}
	if (rc != PAM_SUCCESS) {
		struct msg m;
		msg_init(&m, "failed");
		msg_add(&m, "reason", "account");
		msg_add(&m, "text", pam_strerror(pamh, rc));
		msg_send(daemon_fd, &m);
		msg_free(&m);
		pam_end(pamh, rc);
		return 1;
	}
	send_simple("verified", NULL, NULL);

	/* Which session, then the go-ahead (the greeter left the VT). */
	struct dm_session session = {0};
	const char *extra[16];
	size_t n_extra = 0;
	struct msg start = {0};
	for (;;) {
		struct msg m;
		if (msg_recv(daemon_fd, &m) < 0) {
			pam_end(pamh, PAM_ABORT);
			msg_free(&start);
			dm_session_free(&session);
			return 1;
		}
		const char *type = msg_type(&m);
		if (strcmp(type, "start") == 0) {
			dm_session_free(&session);
			const char *id = msg_get(&m, "session");
			char error[256] = "";
			if (dm_session_find(id ? id : "", h->sessions, &session, error, sizeof error) < 0) {
				send_simple("start-failed", "text", error);
				msg_free(&m);
				continue;
			}
			msg_free(&start);
			start = m;
			n_extra = msg_get_all(&start, "env", extra, 16);
			if (n_extra > 16) n_extra = 16;
			send_simple("ready", NULL, NULL);
			continue;
		}
		if (strcmp(type, "run") == 0 && session.argv) {
			msg_free(&m);
			break;
		}
		msg_free(&m);
		pam_end(pamh, PAM_ABORT);
		msg_free(&start);
		dm_session_free(&session);
		return 1;
	}

	const char *env[32];
	size_t n_env = 0;
	char desktop_names[256] = "";
	if (session.desktop_names && *session.desktop_names) {
		snprintf(desktop_names, sizeof desktop_names, "XDG_CURRENT_DESKTOP=%s", session.desktop_names);
		env[n_env++] = desktop_names;
	}
	for (size_t i = 0; i < n_extra && n_env < 31; i++) {
		if (dm_greeter_env_allowed(extra[i])) env[n_env++] = extra[i];
	}

	struct passwd *pw = NULL;
	if (open_session(pamh, h, "user", session.id) < 0 || !(pw = getpwnam(h->user))) {
		send_simple("ended", "status", "-1");
		pam_end(pamh, PAM_ABORT);
		msg_free(&start);
		dm_session_free(&session);
		return 1;
	}
	int code = run_session(pamh, pw, session.argv, env, n_env, 1);
	close_session(pamh);
	pam_end(pamh, PAM_SUCCESS);
	struct msg m;
	msg_init(&m, "ended");
	msg_add_int(&m, "status", code);
	msg_send(daemon_fd, &m);
	msg_free(&m);
	msg_free(&start);
	dm_session_free(&session);
	return 0;
}

int worker_main(void)
{
	signal(SIGPIPE, SIG_IGN);
	struct hello h = {0};
	if (msg_recv(daemon_fd, &h.m) < 0 || strcmp(msg_type(&h.m), "hello") != 0) return 1;
	h.mode = msg_get(&h.m, "mode");
	h.service = msg_get(&h.m, "service");
	h.user = msg_get(&h.m, "user");
	h.tty = msg_get(&h.m, "tty");
	h.vt = msg_get(&h.m, "vt");
	h.seat = msg_get(&h.m, "seat");
	h.confdir = msg_get(&h.m, "confdir");
	h.sessions = msg_get(&h.m, "sessions");
	if (!h.mode || !h.service || !h.user || !*h.user) return 1;
	int rc = strcmp(h.mode, "greeter") == 0 ? greeter_worker(&h) : user_worker(&h);
	msg_free(&h.m);
	return rc;
}
