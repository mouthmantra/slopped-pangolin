/* Copyright 2026 The dahliaOS Authors
 * SPDX-License-Identifier: Apache-2.0
 *
 * A PAM module for pangolin-dm's tests (never installed): tells something
 * (PAM_TEXT_INFO), then asks for a password and accepts only "secret123". */

#include <stdlib.h>
#include <string.h>

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
	int (*conv)(int, const struct pam_message **, struct pam_response **, void *);
	void *appdata_ptr;
};
int pam_get_item(const pam_handle_t *pamh, int item_type, const void **item);

#define PAM_SUCCESS 0
#define PAM_AUTH_ERR 7
#define PAM_CONV_ERR 19
#define PAM_CONV 5
#define PAM_PROMPT_ECHO_OFF 1
#define PAM_TEXT_INFO 4

static int ask(pam_handle_t *pamh, int style, const char *text, char **answer)
{
	const struct pam_conv *conv = NULL;
	if (pam_get_item(pamh, PAM_CONV, (const void **)&conv) != PAM_SUCCESS || !conv) return PAM_CONV_ERR;
	struct pam_message m = {style, text};
	const struct pam_message *msgs[] = {&m};
	struct pam_response *resp = NULL;
	int rc = conv->conv(1, msgs, &resp, conv->appdata_ptr);
	if (rc != PAM_SUCCESS) return rc;
	if (answer) *answer = resp && resp->resp ? resp->resp : NULL;
	else if (resp) free(resp->resp);
	free(resp);
	return PAM_SUCCESS;
}

int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
	(void)flags;
	(void)argc;
	(void)argv;
	int rc = ask(pamh, PAM_TEXT_INFO, "Testing pangolin-dm", NULL);
	if (rc != PAM_SUCCESS) return rc;
	char *password = NULL;
	rc = ask(pamh, PAM_PROMPT_ECHO_OFF, "Password:", &password);
	if (rc != PAM_SUCCESS) return rc;
	int ok = password && strcmp(password, "secret123") == 0;
	free(password);
	return ok ? PAM_SUCCESS : PAM_AUTH_ERR;
}

int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
	(void)pamh;
	(void)flags;
	(void)argc;
	(void)argv;
	return PAM_SUCCESS;
}
