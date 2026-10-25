/* Copyright 2026 The dahliaOS Authors
 * SPDX-License-Identifier: Apache-2.0 */

#define _GNU_SOURCE
#include "dm.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

void dm_log(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	fputs("pangolin-dm: ", stderr);
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	va_end(ap);
}

void dm_session_free(struct dm_session *s)
{
	free(s->id);
	free(s->name);
	free(s->desktop_names);
	if (s->argv) {
		for (char **a = s->argv; *a; a++) free(*a);
		free(s->argv);
	}
	memset(s, 0, sizeof *s);
}

char **dm_split_exec(const char *exec)
{
	size_t cap = 8, n = 0;
	char **argv = calloc(cap, sizeof *argv);
	size_t len = strlen(exec);
	char *word = malloc(len + 1);
	size_t w = 0;
	int in_word = 0, quoted = 0;
	for (size_t i = 0; i <= len; i++) {
		char c = exec[i];
		if (c == '\0' || (!quoted && (c == ' ' || c == '\t'))) {
			if (in_word) {
				word[w] = '\0';
				/* Field codes stand for files and URLs: none here. */
				if (!(w == 2 && word[0] == '%')) {
					if (n + 2 > cap) argv = realloc(argv, (cap *= 2) * sizeof *argv);
					argv[n++] = strdup(word);
				}
				w = 0;
				in_word = 0;
			}
			continue;
		}
		in_word = 1;
		if (c == '"') {
			quoted = !quoted;
			continue;
		}
		if (c == '\\' && quoted && exec[i + 1]) c = exec[++i];
		if (c == '%' && exec[i + 1] == '%') i++;
		word[w++] = c;
	}
	free(word);
	argv[n] = NULL;
	if (n == 0) {
		free(argv);
		return NULL;
	}
	return argv;
}

/* Reads the [Desktop Entry] of [path] into [out]: 0; -1 when there is no
 * such file; -2 when it can't be started (hidden, no Exec). */
static int read_entry(const char *path, struct dm_session *out)
{
	FILE *f = fopen(path, "re");
	if (!f) return -1;
	char *line = NULL;
	size_t cap = 0;
	int in_entry = 0;
	char *exec = NULL, *try_exec = NULL;
	int hidden = 0;
	while (getline(&line, &cap, f) > 0) {
		line[strcspn(line, "\r\n")] = '\0';
		if (line[0] == '[') {
			in_entry = strcmp(line, "[Desktop Entry]") == 0;
			continue;
		}
		if (!in_entry) continue;
		char *eq = strchr(line, '=');
		if (!eq) continue;
		*eq = '\0';
		const char *key = line, *value = eq + 1;
		if (strcmp(key, "Exec") == 0 && !exec) exec = strdup(value);
		else if (strcmp(key, "TryExec") == 0 && !try_exec) try_exec = strdup(value);
		else if (strcmp(key, "Name") == 0 && !out->name) out->name = strdup(value);
		else if (strcmp(key, "DesktopNames") == 0 && !out->desktop_names) {
			out->desktop_names = strdup(value);
			size_t l = strlen(out->desktop_names);
			while (l > 0 && out->desktop_names[l - 1] == ';') out->desktop_names[--l] = '\0';
			for (char *c = out->desktop_names; *c; c++) {
				if (*c == ';') *c = ':';
			}
		} else if ((strcmp(key, "Hidden") == 0 || strcmp(key, "NoDisplay") == 0) && strcmp(value, "true") == 0) {
			hidden = 1;
		}
	}
	free(line);
	fclose(f);
	(void)try_exec;
	free(try_exec);
	if (hidden || !exec) {
		free(exec);
		return -2;
	}
	out->argv = dm_split_exec(exec);
	free(exec);
	return out->argv ? 0 : -2;
}

int dm_session_find(const char *id, const char *dirs, struct dm_session *out, char *error, size_t error_len)
{
	memset(out, 0, sizeof *out);
	if (!*id || strchr(id, '/') || strstr(id, "..") || strlen(id) > 128) {
		snprintf(error, error_len, "No session \"%s\"", id);
		return -1;
	}
	char *list = strdup(dirs && *dirs ? dirs : "/usr/local/share:/usr/share");
	char *save = NULL;
	for (char *dir = strtok_r(list, ":", &save); dir; dir = strtok_r(NULL, ":", &save)) {
		char path[4096];
		snprintf(path, sizeof path, "%s/wayland-sessions/%s.desktop", dir, id);
		int rc = read_entry(path, out);
		if (rc == 0) {
			out->id = strdup(id);
			free(list);
			return 0;
		}
		dm_session_free(out);
		if (rc == -2) {
			snprintf(error, error_len, "The session \"%s\" can't be started", id);
			free(list);
			return -1;
		}
	}
	free(list);
	snprintf(error, error_len, "No session \"%s\"", id);
	return -1;
}

int dm_greeter_env_allowed(const char *assignment)
{
	/* What Pangolin's greeter sets (PANGOLIN_FROM_GREETER: the desktop
	 * starts on the wallpaper the login screen leaves) and the language;
	 * nothing that could change what runs (PATH, LD_*, ...). */
	static const char *const allowed[] = {
		"PANGOLIN_FROM_GREETER", "LANG", "LANGUAGE", "LC_ALL", "LC_MESSAGES",
	};
	const char *eq = strchr(assignment, '=');
	if (!eq) return 0;
	size_t klen = (size_t)(eq - assignment);
	for (size_t i = 0; i < sizeof allowed / sizeof *allowed; i++) {
		if (strlen(allowed[i]) == klen && strncmp(assignment, allowed[i], klen) == 0) return 1;
	}
	return 0;
}
