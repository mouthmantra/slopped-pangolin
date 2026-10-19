// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0

#include "check_password.h"

#include <dlfcn.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>

// The shell's lock screen checks passwords in a process of its own (this,
// started as `pangolin --check-password`): in the shell's, the Dart VM reaps
// every child process, so pam_unix lost the exit status of its unix_chkpwd
// helper ("waitpid returned -1: No child processes") and turned right
// passwords down at random.
//
// libpam is loaded at runtime, as before: no build dependency on its headers.

namespace {

constexpr int kPamSuccess = 0;
constexpr int kPamConvErr = 19;
constexpr int kPamPromptEchoOff = 1;
constexpr int kPamPromptEchoOn = 2;
constexpr int kPamRefreshCred = 0x0010;

struct PamMessage {
  int msg_style;
  const char* msg;
};

struct PamResponse {
  char* resp;
  int resp_retcode;
};

struct PamConv {
  int (*conv)(int, const PamMessage**, PamResponse**, void*);
  void* appdata_ptr;
};

using PamStart = int (*)(const char*, const char*, const PamConv*, void**);
using PamHandleInt = int (*)(void*, int);
using PamStrerror = const char* (*)(void*, int);

// Answers every prompt with the password (PAM frees the answers).
int converse(int count,
             const PamMessage** messages,
             PamResponse** responses,
             void* password) {
  if (count <= 0) return kPamConvErr;
  auto* answers =
      static_cast<PamResponse*>(calloc(count, sizeof(PamResponse)));
  if (answers == nullptr) return kPamConvErr;
  for (int i = 0; i < count; i++) {
    const int style = messages[i]->msg_style;
    if (style == kPamPromptEchoOff || style == kPamPromptEchoOn) {
      answers[i].resp = strdup(static_cast<const char*>(password));
    }
  }
  *responses = answers;
  return kPamSuccess;
}

}  // namespace

int pangolin_check_password(const char* service, const char* user) {
  static char password[4096];
  const size_t length = fread(password, 1, sizeof password - 1, stdin);
  password[length] = '\0';

  int result = 2;
  void* pam = dlopen("libpam.so.0", RTLD_NOW);
  if (pam != nullptr) {
    auto start = reinterpret_cast<PamStart>(dlsym(pam, "pam_start"));
    auto authenticate =
        reinterpret_cast<PamHandleInt>(dlsym(pam, "pam_authenticate"));
    auto account = reinterpret_cast<PamHandleInt>(dlsym(pam, "pam_acct_mgmt"));
    auto credentials =
        reinterpret_cast<PamHandleInt>(dlsym(pam, "pam_setcred"));
    auto end = reinterpret_cast<PamHandleInt>(dlsym(pam, "pam_end"));
    auto describe = reinterpret_cast<PamStrerror>(dlsym(pam, "pam_strerror"));
    const PamConv conversation = {converse, password};
    void* handle = nullptr;
    if (start != nullptr && authenticate != nullptr && account != nullptr &&
        credentials != nullptr && end != nullptr && describe != nullptr &&
        start(service, user, &conversation, &handle) == kPamSuccess) {
      int status = authenticate(handle, 0);
      if (status == kPamSuccess) status = account(handle, 0);
      // Refreshes credentials such as Kerberos tickets, as screen lockers do.
      if (status == kPamSuccess) credentials(handle, kPamRefreshCred);
      if (status != kPamSuccess) {
        fprintf(stderr, "pangolin: password not accepted: %s\n",
                describe(handle, status));
      }
      end(handle, status);
      result = status == kPamSuccess ? 0 : 1;
    } else {
      fprintf(stderr, "pangolin: PAM service %s can't be used\n", service);
    }
  }
  explicit_bzero(password, sizeof password);
  return result;
}
