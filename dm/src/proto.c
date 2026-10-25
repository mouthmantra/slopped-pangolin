/* Copyright 2026 The dahliaOS Authors
 * SPDX-License-Identifier: Apache-2.0 */

#define _GNU_SOURCE
#include "proto.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static void *xrealloc(void *p, size_t size)
{
	void *out = realloc(p, size);
	if (!out) {
		perror("pangolin-dm: out of memory");
		abort();
	}
	return out;
}

static void append(struct msg *m, const char *s)
{
	size_t n = strlen(s) + 1;
	if (m->len + n > m->cap) {
		while (m->len + n > m->cap) m->cap = m->cap ? 2 * m->cap : 256;
		m->data = xrealloc(m->data, m->cap);
	}
	memcpy(m->data + m->len, s, n);
	m->len += n;
}

void msg_init(struct msg *m, const char *type)
{
	m->data = NULL;
	m->len = 0;
	m->cap = 0;
	if (type) msg_add(m, "type", type);
}

void msg_free(struct msg *m)
{
	/* Answers can be passwords. */
	if (m->data) explicit_bzero(m->data, m->cap);
	free(m->data);
	m->data = NULL;
	m->len = m->cap = 0;
}

void msg_add(struct msg *m, const char *key, const char *value)
{
	append(m, key);
	append(m, value ? value : "");
}

void msg_add_int(struct msg *m, const char *key, long value)
{
	char buf[32];
	snprintf(buf, sizeof buf, "%ld", value);
	msg_add(m, key, buf);
}

/* The value of the [skip]th pair with [key], or NULL. */
static const char *find(const struct msg *m, const char *key, size_t skip)
{
	size_t i = 0;
	while (i < m->len) {
		const char *k = m->data + i;
		size_t klen = strnlen(k, m->len - i);
		if (i + klen >= m->len) return NULL;
		const char *v = k + klen + 1;
		size_t vlen = strnlen(v, m->len - (size_t)(v - m->data));
		if ((size_t)(v - m->data) + vlen >= m->len) return NULL;
		if (strcmp(k, key) == 0) {
			if (skip == 0) return v;
			skip--;
		}
		i = (size_t)(v - m->data) + vlen + 1;
	}
	return NULL;
}

const char *msg_get(const struct msg *m, const char *key)
{
	return find(m, key, 0);
}

const char *msg_type(const struct msg *m)
{
	const char *t = msg_get(m, "type");
	return t ? t : "";
}

size_t msg_get_all(const struct msg *m, const char *key, const char **out, size_t max)
{
	size_t n = 0;
	for (;;) {
		const char *v = find(m, key, n);
		if (!v) return n;
		if (n < max) out[n] = v;
		n++;
	}
}

static int write_all(int fd, const void *buf, size_t len)
{
	const char *p = buf;
	while (len > 0) {
		ssize_t w = send(fd, p, len, MSG_NOSIGNAL);
		if (w < 0 && errno == ENOTSOCK) w = write(fd, p, len);
		if (w < 0) {
			if (errno == EINTR) continue;
			return -1;
		}
		p += w;
		len -= (size_t)w;
	}
	return 0;
}

static int read_all(int fd, void *buf, size_t len)
{
	char *p = buf;
	while (len > 0) {
		ssize_t r = read(fd, p, len);
		if (r < 0 && errno == EINTR) continue;
		if (r <= 0) return -1;
		p += r;
		len -= (size_t)r;
	}
	return 0;
}

static void put_le32(unsigned char *out, uint32_t v)
{
	out[0] = v & 0xff;
	out[1] = (v >> 8) & 0xff;
	out[2] = (v >> 16) & 0xff;
	out[3] = (v >> 24) & 0xff;
}

static uint32_t get_le32(const unsigned char *in)
{
	return (uint32_t)in[0] | (uint32_t)in[1] << 8 | (uint32_t)in[2] << 16 | (uint32_t)in[3] << 24;
}

int msg_send(int fd, const struct msg *m)
{
	if (m->len > MSG_MAX) {
		errno = EMSGSIZE;
		return -1;
	}
	unsigned char head[4];
	put_le32(head, (uint32_t)m->len);
	if (write_all(fd, head, 4) < 0) return -1;
	return write_all(fd, m->data, m->len);
}

int msg_recv(int fd, struct msg *m)
{
	unsigned char head[4];
	msg_init(m, NULL);
	if (read_all(fd, head, 4) < 0) return -1;
	uint32_t len = get_le32(head);
	if (len > MSG_MAX) return -1;
	m->data = xrealloc(NULL, len ? len : 1);
	m->cap = len ? len : 1;
	if (read_all(fd, m->data, len) < 0) {
		msg_free(m);
		return -1;
	}
	m->len = len;
	return 0;
}

void reader_init(struct reader *r)
{
	r->buf = xrealloc(NULL, MSG_MAX + 4);
	r->len = 0;
}

void reader_free(struct reader *r)
{
	if (r->buf) explicit_bzero(r->buf, MSG_MAX + 4);
	free(r->buf);
	r->buf = NULL;
	r->len = 0;
}

int reader_fill(struct reader *r, int fd)
{
	if (r->len >= MSG_MAX + 4) return -1;
	ssize_t n = recv(fd, r->buf + r->len, MSG_MAX + 4 - r->len, MSG_DONTWAIT);
	if (n < 0) return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? 0 : -1;
	if (n == 0) return -1;
	r->len += (size_t)n;
	if (r->len >= 4 && get_le32((unsigned char *)r->buf) > MSG_MAX) return -1;
	return 0;
}

int reader_next(struct reader *r, struct msg *m)
{
	if (r->len < 4) return 0;
	uint32_t len = get_le32((unsigned char *)r->buf);
	if (r->len < 4 + (size_t)len) return 0;
	msg_init(m, NULL);
	m->data = xrealloc(NULL, len ? len : 1);
	m->cap = len ? len : 1;
	memcpy(m->data, r->buf + 4, len);
	m->len = len;
	memmove(r->buf, r->buf + 4 + len, r->len - 4 - len);
	explicit_bzero(r->buf + r->len - 4 - len, 4 + len);
	r->len -= 4 + len;
	return 1;
}
