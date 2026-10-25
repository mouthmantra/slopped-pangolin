/* Copyright 2026 The dahliaOS Authors
 * SPDX-License-Identifier: Apache-2.0
 *
 * Messages of pangolin-dm: between the daemon and its session workers, and
 * between the daemon and the greeter. A frame is a 32 bit little endian
 * length, then that many bytes of "key NUL value NUL" pairs. The first pair
 * is the type ("type", e.g. "begin"); keys may repeat (arguments). See
 * docs/DISPLAY_MANAGER.md. */

#ifndef PANGOLIN_DM_PROTO_H
#define PANGOLIN_DM_PROTO_H

#include <stddef.h>

/* The largest frame either side accepts. */
#define MSG_MAX 65536

struct msg {
	char *data;
	size_t len;
	size_t cap;
};

/* A new message of [type]. */
void msg_init(struct msg *m, const char *type);
void msg_free(struct msg *m);
void msg_add(struct msg *m, const char *key, const char *value);
void msg_add_int(struct msg *m, const char *key, long value);

/* The message's type, "" when it has none. */
const char *msg_type(const struct msg *m);
/* The first value of [key], or NULL. */
const char *msg_get(const struct msg *m, const char *key);
/* The values of [key], in order, up to [max]; how many there were. */
size_t msg_get_all(const struct msg *m, const char *key, const char **out, size_t max);

/* Sends [m] on a blocking descriptor; 0, or -1 with errno. */
int msg_send(int fd, const struct msg *m);
/* Reads one message from a blocking descriptor; 0, or -1 (closed or bad). */
int msg_recv(int fd, struct msg *m);

/* Frames read from a non-blocking descriptor as they come. */
struct reader {
	char *buf;
	size_t len;
};

void reader_init(struct reader *r);
void reader_free(struct reader *r);
/* Reads what is there; -1 when the other end closed or sent a bad frame. */
int reader_fill(struct reader *r, int fd);
/* The next complete message into [m] (1), or 0 when there is none yet. */
int reader_next(struct reader *r, struct msg *m);

#endif
