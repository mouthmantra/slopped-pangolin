// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0

#ifndef PANGOLIN_CHECK_PASSWORD_H_
#define PANGOLIN_CHECK_PASSWORD_H_

// Checks the password read from standard input for [user] with the PAM
// [service]. Returns the exit status for the lock screen (lib/services/
// pam.dart): 0 right, 1 wrong, 2 not checkable (no PAM).
int pangolin_check_password(const char* service, const char* user);

#endif  // PANGOLIN_CHECK_PASSWORD_H_
