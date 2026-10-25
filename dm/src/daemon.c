/* Copyright 2026 The dahliaOS Authors
 * SPDX-License-Identifier: Apache-2.0
 *
 * pangolin-dm's daemon (GDM's main process): runs as root from
 * pangolin-dm.service, owns the VT, keeps a greeter running on it as the
 * greeter user (in its own logind session, class greeter), and answers the
 * greeter on a socket only that user can reach. A login runs in a session
 * worker (worker.c); the daemon relays its questions to the greeter and,
 * once the user is verified and the greeter has left the screen, tells it
 * to start the session. When the session ends, the greeter comes back.
 *
 * Greeter requests and the replies (one each), see docs/DISPLAY_MANAGER.md:
 *   begin user [service]   -> question | message | verified | failed
 *   answer [text]          -> question | message | verified | failed
 *   start session [env...] -> started | error   (then the greeter exits)
 *   cancel                 -> ok */

#define _GNU_SOURCE
#include "dm.h"
#include "proto.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/vt.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef GREETER_COMMAND
#define GREETER_COMMAND "/usr/bin/pangolin-greeter"
#endif

struct options {
	int test;
	int once;
	const char *run_dir;
	const char *confdir;
	const char *greeter;
	const char *greeter_user;
	const char *sessions;
	const char *seat;
	int vt;
};

struct worker {
	pid_t pid;
	int fd;
	struct reader rd;
	/* The session it runs, once running. */
	pid_t session;
};

enum login_state { IDLE, CONVERSING, VERIFIED, READY, RUNNING };

static struct {
	struct options o;
	char socket_path[108];
	int listen_fd;
	int conn_fd;
	struct reader conn_rd;
	uid_t greeter_uid;
	int vt_fd;
	char tty[16];
	char vt[8];

	struct worker greeter;
	struct worker login;
	enum login_state state;
	/* A greeter request waits for the login worker's next event. */
	int pending;
	/* The worker waits for an answer (to a question or message). */
	int awaiting;

	/* The greeter must leave once the session is ready. */
	time_t greeter_deadline;
	/* When to start the greeter again (after it exited or crashed). */
	time_t greeter_restart;
	time_t greeter_starts[5];
	/* The user's session ended: the greeter comes back once its worker is
	 * done (it closes the PAM session last). */
	int session_over;
	int quit;
} dm;

static time_t now(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec;
}

static void reply(const struct msg *m)
{
	if (dm.conn_fd >= 0 && msg_send(dm.conn_fd, m) < 0) dm_log("greeter: %s", strerror(errno));
}

static void reply_simple(const char *type, const char *key, const char *value)
{
	struct msg m;
	msg_init(&m, type);
	if (key) msg_add(&m, key, value);
	reply(&m);
	msg_free(&m);
}

static int spawn_worker(struct worker *w, const struct msg *hello)
{
	int sv[2];
	if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv) < 0) {
		dm_log("socketpair: %s", strerror(errno));
		return -1;
	}
	pid_t pid = fork();
	if (pid < 0) {
		dm_log("fork: %s", strerror(errno));
		close(sv[0]);
		close(sv[1]);
		return -1;
	}
	if (pid == 0) {
		sigset_t all;
		sigemptyset(&all);
		sigprocmask(SIG_SETMASK, &all, NULL);
		if (dup2(sv[1], 3) < 0) _exit(1);
		close_range(4, ~0U, 0);
		char *argv[] = {"pangolin-dm", "--worker", NULL};
		execv("/proc/self/exe", argv);
		_exit(127);
	}
	close(sv[1]);
	w->pid = pid;
	w->fd = sv[0];
	w->session = 0;
	reader_init(&w->rd);
	if (msg_send(w->fd, hello) < 0) dm_log("worker: %s", strerror(errno));
	return 0;
}

/* A worker is gone once its socket closed; its pid may be reaped before. */
static void drop_worker(struct worker *w, int kill_it)
{
	if (w->pid > 0 && kill_it) kill(w->pid, SIGTERM);
	if (w->fd >= 0) close(w->fd);
	reader_free(&w->rd);
	w->fd = -1;
	w->pid = 0;
	w->session = 0;
}

static void add_common(struct msg *hello)
{
	msg_add(hello, "tty", dm.tty);
	msg_add(hello, "vt", dm.vt);
	msg_add(hello, "seat", dm.o.seat);
	if (dm.o.confdir) msg_add(hello, "confdir", dm.o.confdir);
	if (dm.o.sessions) msg_add(hello, "sessions", dm.o.sessions);
}

static void start_greeter(void)
{
	time_t t = now();
	/* Five starts within half a minute: wait before trying again. */
	if (dm.greeter_starts[0] && t - dm.greeter_starts[0] < 30) {
		dm_log("greeter: crashing repeatedly, waiting");
		dm.greeter_restart = t + 30;
		memset(dm.greeter_starts, 0, sizeof dm.greeter_starts);
		return;
	}
	memmove(dm.greeter_starts, dm.greeter_starts + 1, sizeof dm.greeter_starts - sizeof *dm.greeter_starts);
	dm.greeter_starts[4] = t;
	dm.greeter_restart = 0;

	struct msg hello;
	msg_init(&hello, "hello");
	msg_add(&hello, "mode", "greeter");
	msg_add(&hello, "service", "pangolin-dm-greeter");
	msg_add(&hello, "user", dm.o.greeter_user);
	add_common(&hello);
	char **args = dm_split_exec(dm.o.greeter);
	for (char **a = args; a && *a; a++) msg_add(&hello, "arg", *a);
	for (char **a = args; a && *a; a++) free(*a);
	free(args);
	char sock[160];
	snprintf(sock, sizeof sock, "PANGOLIN_DM_SOCK=%s", dm.socket_path);
	msg_add(&hello, "env", sock);
	if (spawn_worker(&dm.greeter, &hello) < 0) dm.greeter_restart = t + 5;
	msg_free(&hello);
	dm_log("greeter: started");
}

static void cancel_login(void)
{
	if (dm.login.fd >= 0 && dm.state != RUNNING) drop_worker(&dm.login, 1);
	if (dm.state != RUNNING) dm.state = IDLE;
	dm.pending = 0;
	dm.awaiting = 0;
}

static void begin(const struct msg *req)
{
	const char *user = msg_get(req, "user");
	const char *service = msg_get(req, "service");
	if (dm.state == RUNNING || dm.state == READY) {
		reply_simple("failed", "reason", "error");
		return;
	}
	if (!user || !*user || strlen(user) > 256 || strchr(user, '/')) {
		reply_simple("failed", "reason", "error");
		return;
	}
	/* Only the password service so far; fingerprint and smartcard come as
	 * their own PAM services, conversations next to this one. */
	if (service && *service && strcmp(service, "password") != 0) {
		reply_simple("failed", "reason", "error");
		return;
	}
	cancel_login();
	struct msg hello;
	msg_init(&hello, "hello");
	msg_add(&hello, "mode", "user");
	msg_add(&hello, "service", "pangolin-dm");
	msg_add(&hello, "user", user);
	add_common(&hello);
	int rc = spawn_worker(&dm.login, &hello);
	msg_free(&hello);
	if (rc < 0) {
		reply_simple("failed", "reason", "error");
		return;
	}
	dm.state = CONVERSING;
	dm.pending = 1;
}

static void answer(const struct msg *req)
{
	if (dm.state != CONVERSING || !dm.awaiting) {
		reply_simple("failed", "reason", "error");
		return;
	}
	struct msg m;
	msg_init(&m, "answer");
	const char *text = msg_get(req, "text");
	if (text) msg_add(&m, "text", text);
	msg_send(dm.login.fd, &m);
	msg_free(&m);
	dm.awaiting = 0;
	dm.pending = 1;
}

static void start(const struct msg *req)
{
	if (dm.state != VERIFIED && dm.state != READY) {
		reply_simple("error", "text", "Not logged in");
		return;
	}
	struct msg m;
	msg_init(&m, "start");
	const char *session = msg_get(req, "session");
	msg_add(&m, "session", session ? session : "");
	const char *env[16];
	size_t n = msg_get_all(req, "env", env, 16);
	for (size_t i = 0; i < n && i < 16; i++) {
		if (dm_greeter_env_allowed(env[i])) msg_add(&m, "env", env[i]);
	}
	msg_send(dm.login.fd, &m);
	msg_free(&m);
	dm.pending = 1;
}

static void handle_request(const struct msg *req)
{
	const char *type = msg_type(req);
	if (dm.pending) {
		reply_simple("error", "text", "Busy");
		return;
	}
	if (strcmp(type, "begin") == 0) begin(req);
	else if (strcmp(type, "answer") == 0) answer(req);
	else if (strcmp(type, "start") == 0) start(req);
	else if (strcmp(type, "cancel") == 0) {
		cancel_login();
		reply_simple("ok", NULL, NULL);
	} else reply_simple("error", "text", "Unknown request");
}

/* The greeter left the screen: the session can take it. */
static void greeter_gone(void)
{
	if (dm.conn_fd >= 0) {
		close(dm.conn_fd);
		dm.conn_fd = -1;
		reader_free(&dm.conn_rd);
	}
	dm.greeter_deadline = 0;
	if (dm.state == READY) {
		struct msg m;
		msg_init(&m, "run");
		msg_send(dm.login.fd, &m);
		msg_free(&m);
		dm.state = RUNNING;
		dm_log("session: starting");
		return;
	}
	/* Gone without a login (crashed, or quit): back it comes. */
	cancel_login();
	if (dm.o.once) {
		dm_log("greeter: exited without a login");
		dm.quit = 2;
		return;
	}
	dm.greeter_restart = now() + 1;
}

static void handle_login_event(const struct msg *ev)
{
	const char *type = msg_type(ev);
	if (strcmp(type, "question") == 0 || strcmp(type, "message") == 0) {
		dm.awaiting = 1;
		dm.pending = 0;
		reply(ev);
	} else if (strcmp(type, "verified") == 0) {
		dm.state = VERIFIED;
		dm.pending = 0;
		reply_simple("verified", NULL, NULL);
	} else if (strcmp(type, "failed") == 0) {
		dm.pending = 0;
		dm.state = IDLE;
		reply(ev);
	} else if (strcmp(type, "start-failed") == 0) {
		dm.pending = 0;
		const char *text = msg_get(ev, "text");
		reply_simple("error", "text", text ? text : "Can't start the session");
	} else if (strcmp(type, "ready") == 0) {
		dm.pending = 0;
		dm.state = READY;
		reply_simple("started", NULL, NULL);
		/* The greeter fades out and exits; past the deadline it's made
		 * to. */
		dm.greeter_deadline = now() + 10;
	} else if (strcmp(type, "running") == 0) {
		const char *pid = msg_get(ev, "pid");
		dm.login.session = pid ? atoi(pid) : 0;
		dm_log("session: running");
	} else if (strcmp(type, "ended") == 0) {
		dm_log("session: ended (%s)", msg_get(ev, "status") ? msg_get(ev, "status") : "?");
		dm.session_over = dm.state == RUNNING;
		dm.state = IDLE;
	}
}

static void handle_greeter_event(const struct msg *ev)
{
	const char *type = msg_type(ev);
	if (strcmp(type, "running") == 0) {
		const char *pid = msg_get(ev, "pid");
		dm.greeter.session = pid ? atoi(pid) : 0;
	} else if (strcmp(type, "ended") == 0) {
		dm_log("greeter: ended (%s)", msg_get(ev, "status") ? msg_get(ev, "status") : "?");
	}
}

static void login_worker_closed(void)
{
	int session_over = dm.session_over || dm.state == RUNNING;
	dm.session_over = 0;
	drop_worker(&dm.login, 0);
	if (dm.pending) {
		dm.pending = 0;
		struct msg m;
		msg_init(&m, "failed");
		msg_add(&m, "reason", "error");
		msg_add(&m, "text", "The login stopped");
		reply(&m);
		msg_free(&m);
	}
	dm.awaiting = 0;
	dm.state = IDLE;
	if (session_over) {
		if (dm.o.once) {
			dm.quit = 1;
			return;
		}
		if (dm.greeter.fd < 0) start_greeter();
	}
}

static void accept_greeter(void)
{
	int fd = accept4(dm.listen_fd, NULL, NULL, SOCK_CLOEXEC);
	if (fd < 0) return;
	struct ucred cred = {0};
	socklen_t len = sizeof cred;
	if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) < 0 || cred.uid != dm.greeter_uid) {
		dm_log("greeter: refused a connection from uid %d", (int)cred.uid);
		close(fd);
		return;
	}
	if (dm.conn_fd >= 0) {
		close(dm.conn_fd);
		reader_free(&dm.conn_rd);
	}
	dm.conn_fd = fd;
	reader_init(&dm.conn_rd);
}

static int setup_socket(void)
{
	if (mkdir(dm.o.run_dir, 0711) < 0 && errno != EEXIST) {
		dm_log("%s: %s", dm.o.run_dir, strerror(errno));
		return -1;
	}
	if (snprintf(dm.socket_path, sizeof dm.socket_path, "%s/greeter.sock", dm.o.run_dir) >= (int)sizeof dm.socket_path) {
		dm_log("socket path too long");
		return -1;
	}
	unlink(dm.socket_path);
	dm.listen_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	struct sockaddr_un addr = {.sun_family = AF_UNIX};
	strcpy(addr.sun_path, dm.socket_path);
	mode_t old = umask(0177);
	int rc = bind(dm.listen_fd, (struct sockaddr *)&addr, sizeof addr);
	umask(old);
	if (rc < 0 || listen(dm.listen_fd, 4) < 0) {
		dm_log("%s: %s", dm.socket_path, strerror(errno));
		return -1;
	}
	if (geteuid() == 0 && chown(dm.socket_path, dm.greeter_uid, (gid_t)-1) < 0) {
		dm_log("chown %s: %s", dm.socket_path, strerror(errno));
		return -1;
	}
	return 0;
}

/* The VT the greeter and sessions use, made the active one. */
static void setup_vt(void)
{
	if (dm.o.test || dm.o.vt <= 0) return;
	snprintf(dm.tty, sizeof dm.tty, "tty%d", dm.o.vt);
	snprintf(dm.vt, sizeof dm.vt, "%d", dm.o.vt);
	char path[32];
	snprintf(path, sizeof path, "/dev/tty%d", dm.o.vt);
	dm.vt_fd = open(path, O_RDWR | O_NOCTTY | O_CLOEXEC);
	if (dm.vt_fd < 0) {
		dm_log("%s: %s", path, strerror(errno));
		return;
	}
	if (ioctl(dm.vt_fd, VT_ACTIVATE, dm.o.vt) < 0 || ioctl(dm.vt_fd, VT_WAITACTIVE, dm.o.vt) < 0) {
		dm_log("VT %d: %s", dm.o.vt, strerror(errno));
	}
}

static void usage(void)
{
	fputs("usage: pangolin-dm [--vt N] [--seat NAME] [--greeter CMD] [--greeter-user USER]\n"
	      "                   [--run-dir DIR] [--sessions DIRS]\n"
	      "       pangolin-dm --test [--once] [--pam-confdir DIR] ...  (as any user, no VT)\n",
	      stderr);
}

int daemon_main(int argc, char **argv)
{
	dm.o = (struct options){
		.run_dir = "/run/pangolin-dm",
		.greeter = GREETER_COMMAND,
		.greeter_user = "pangolin-greeter",
		.seat = "seat0",
		.vt = 1,
	};
	for (int i = 1; i < argc; i++) {
		const char *a = argv[i];
		const char *next = i + 1 < argc ? argv[i + 1] : NULL;
		if (strcmp(a, "--test") == 0) dm.o.test = 1;
		else if (strcmp(a, "--once") == 0) dm.o.once = 1;
		else if (strcmp(a, "--run-dir") == 0 && next) dm.o.run_dir = argv[++i];
		else if (strcmp(a, "--pam-confdir") == 0 && next) dm.o.confdir = argv[++i];
		else if (strcmp(a, "--greeter") == 0 && next) dm.o.greeter = argv[++i];
		else if (strcmp(a, "--greeter-user") == 0 && next) dm.o.greeter_user = argv[++i];
		else if (strcmp(a, "--sessions") == 0 && next) dm.o.sessions = argv[++i];
		else if (strcmp(a, "--seat") == 0 && next) dm.o.seat = argv[++i];
		else if (strcmp(a, "--vt") == 0 && next) dm.o.vt = atoi(argv[++i]);
		else {
			usage();
			return 2;
		}
	}
	if (!dm.o.test && geteuid() != 0) {
		dm_log("must run as root (or with --test)");
		return 1;
	}
	if (dm.o.test) {
		/* The greeter and sessions run as whoever runs the test. */
		struct passwd *pw = getpwuid(getuid());
		if (!pw) return 1;
		dm.o.greeter_user = strdup(pw->pw_name);
	}
	struct passwd *gp = getpwnam(dm.o.greeter_user);
	if (!gp) {
		dm_log("no greeter user %s", dm.o.greeter_user);
		return 1;
	}
	dm.greeter_uid = gp->pw_uid;
	dm.conn_fd = -1;
	dm.vt_fd = -1;
	dm.greeter.fd = dm.login.fd = -1;

	sigset_t mask;
	sigemptyset(&mask);
	sigaddset(&mask, SIGCHLD);
	sigaddset(&mask, SIGTERM);
	sigaddset(&mask, SIGINT);
	sigaddset(&mask, SIGHUP);
	sigprocmask(SIG_BLOCK, &mask, NULL);
	signal(SIGPIPE, SIG_IGN);
	int sfd = signalfd(-1, &mask, SFD_CLOEXEC);

	if (setup_socket() < 0) return 1;
	setup_vt();
	start_greeter();

	while (!dm.quit) {
		struct pollfd fds[5];
		int n = 0;
		fds[n++] = (struct pollfd){.fd = sfd, .events = POLLIN};
		fds[n++] = (struct pollfd){.fd = dm.listen_fd, .events = POLLIN};
		int conn_i = -1, greeter_i = -1, login_i = -1;
		if (dm.conn_fd >= 0) {
			conn_i = n;
			fds[n++] = (struct pollfd){.fd = dm.conn_fd, .events = POLLIN};
		}
		if (dm.greeter.fd >= 0) {
			greeter_i = n;
			fds[n++] = (struct pollfd){.fd = dm.greeter.fd, .events = POLLIN};
		}
		if (dm.login.fd >= 0) {
			login_i = n;
			fds[n++] = (struct pollfd){.fd = dm.login.fd, .events = POLLIN};
		}
		int timeout = -1;
		time_t t = now();
		if (dm.greeter_deadline) timeout = dm.greeter_deadline > t ? (int)(dm.greeter_deadline - t) * 1000 : 0;
		if (dm.greeter_restart) {
			int r = dm.greeter_restart > t ? (int)(dm.greeter_restart - t) * 1000 : 0;
			if (timeout < 0 || r < timeout) timeout = r;
		}
		if (poll(fds, (nfds_t)n, timeout) < 0 && errno != EINTR) break;

		t = now();
		if (dm.greeter_deadline && t >= dm.greeter_deadline) {
			dm_log("greeter: didn't leave, ending it");
			if (dm.greeter.session > 0) kill(dm.greeter.session, SIGTERM);
			dm.greeter_deadline = 0;
		}
		if (dm.greeter_restart && t >= dm.greeter_restart && dm.greeter.fd < 0 && dm.state != RUNNING) start_greeter();

		if (fds[0].revents & POLLIN) {
			struct signalfd_siginfo si;
			while (read(sfd, &si, sizeof si) == sizeof si) {
				if (si.ssi_signo == SIGCHLD) {
					pid_t pid;
					while ((pid = waitpid(-1, NULL, WNOHANG)) > 0) {
						if (pid == dm.greeter.pid) dm.greeter.pid = 0;
						if (pid == dm.login.pid) dm.login.pid = 0;
					}
				} else {
					dm_log("stopping");
					dm.quit = 1;
				}
				break;
			}
		}
		if (fds[1].revents & POLLIN) accept_greeter();
		if (conn_i >= 0 && fds[conn_i].revents) {
			if (reader_fill(&dm.conn_rd, dm.conn_fd) < 0) {
				close(dm.conn_fd);
				dm.conn_fd = -1;
				reader_free(&dm.conn_rd);
				/* A greeter that went away takes its login along. */
				if (dm.state == CONVERSING || dm.state == VERIFIED) cancel_login();
			} else {
				struct msg req;
				while (dm.conn_fd >= 0 && reader_next(&dm.conn_rd, &req)) {
					handle_request(&req);
					msg_free(&req);
				}
			}
		}
		if (login_i >= 0 && fds[login_i].revents) {
			if (reader_fill(&dm.login.rd, dm.login.fd) < 0) {
				login_worker_closed();
			} else {
				struct msg ev;
				while (dm.login.fd >= 0 && reader_next(&dm.login.rd, &ev)) {
					handle_login_event(&ev);
					msg_free(&ev);
				}
			}
		}
		if (greeter_i >= 0 && fds[greeter_i].revents) {
			if (reader_fill(&dm.greeter.rd, dm.greeter.fd) < 0) {
				drop_worker(&dm.greeter, 0);
				greeter_gone();
			} else {
				struct msg ev;
				while (dm.greeter.fd >= 0 && reader_next(&dm.greeter.rd, &ev)) {
					handle_greeter_event(&ev);
					msg_free(&ev);
				}
			}
		}
	}

	if (dm.greeter.session > 0) kill(dm.greeter.session, SIGTERM);
	if (dm.login.session > 0) kill(dm.login.session, SIGTERM);
	if (dm.greeter.pid > 0) kill(dm.greeter.pid, SIGTERM);
	if (dm.login.pid > 0) kill(dm.login.pid, SIGTERM);
	unlink(dm.socket_path);
	return dm.quit == 2 ? 1 : 0;
}

int main(int argc, char **argv)
{
	if (argc == 2 && strcmp(argv[1], "--worker") == 0) return worker_main();
	return daemon_main(argc, argv);
}
