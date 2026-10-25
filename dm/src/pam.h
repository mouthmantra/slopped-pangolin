/* Copyright 2026 The dahliaOS Authors
 * SPDX-License-Identifier: Apache-2.0
 *
 * The part of the Linux-PAM application interface pangolin-dm uses, declared
 * here so that building needs only the library (libpam.so.0), not its
 * development headers. Values as in <security/_pam_types.h>, unchanged for
 * decades. */

#ifndef PANGOLIN_DM_PAM_H
#define PANGOLIN_DM_PAM_H

typedef struct pam_handle pam_handle_t;

struct pam_message {
	int msg_style;
	const char *msg;
};

struct pam_response {
	char *resp;
	int resp_retcode;
};

struct pam_conv {
	int (*conv)(int num_msg, const struct pam_message **msg,
		struct pam_response **resp, void *appdata_ptr);
	void *appdata_ptr;
};

#define PAM_SUCCESS 0
#define PAM_BUF_ERR 5
#define PAM_AUTH_ERR 7
#define PAM_MAXTRIES 11
#define PAM_NEW_AUTHTOK_REQD 12
#define PAM_ACCT_EXPIRED 13
#define PAM_CONV_ERR 19
#define PAM_ABORT 26

#define PAM_ESTABLISH_CRED 0x0002
#define PAM_DELETE_CRED 0x0004
#define PAM_REINITIALIZE_CRED 0x0008
#define PAM_CHANGE_EXPIRED_AUTHTOK 0x0020

#define PAM_TTY 3
#define PAM_XDISPLAY 11

#define PAM_PROMPT_ECHO_OFF 1
#define PAM_PROMPT_ECHO_ON 2
#define PAM_ERROR_MSG 3
#define PAM_TEXT_INFO 4

int pam_start(const char *service, const char *user,
	const struct pam_conv *conv, pam_handle_t **pamh);
/* Linux-PAM 1.4 and later: services from [confdir] (pangolin-dm's tests). */
int pam_start_confdir(const char *service, const char *user,
	const struct pam_conv *conv, const char *confdir, pam_handle_t **pamh);
int pam_end(pam_handle_t *pamh, int status);
int pam_authenticate(pam_handle_t *pamh, int flags);
int pam_acct_mgmt(pam_handle_t *pamh, int flags);
int pam_chauthtok(pam_handle_t *pamh, int flags);
int pam_setcred(pam_handle_t *pamh, int flags);
int pam_open_session(pam_handle_t *pamh, int flags);
int pam_close_session(pam_handle_t *pamh, int flags);
int pam_set_item(pam_handle_t *pamh, int item_type, const void *item);
int pam_get_item(const pam_handle_t *pamh, int item_type, const void **item);
int pam_putenv(pam_handle_t *pamh, const char *name_value);
char **pam_getenvlist(pam_handle_t *pamh);
const char *pam_strerror(pam_handle_t *pamh, int errnum);

#endif
