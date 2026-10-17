// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0
//
// Locks the session with ext-session-lock-v1 and shows a Flutter view on
// every monitor as the lock screen. The compositor (river) keeps the session
// locked, showing nothing else and sending input nowhere else, until the
// lock is released; if the shell dies meanwhile the session stays locked.

#ifndef PANGOLIN_SESSION_LOCK_H_
#define PANGOLIN_SESSION_LOCK_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <vector>

struct SessionLockDelegate {
  // "locked": every monitor shows the lock screen; "denied": the compositor
  // refused to lock (another locker); "unlocked".
  void (*state_changed)(const char* state, void* user_data);
  // The lock screen views (one per monitor) changed.
  void (*views_changed)(void* user_data);
  void* user_data;
};

// Whether the compositor supports ext-session-lock-v1.
bool session_lock_supported();

// Locks the session, creating the lock screen views on [engine]. False when
// already locked or unsupported.
bool session_lock_lock(GtkApplication* application, FlEngine* engine,
                       const SessionLockDelegate& delegate);

// Unlocks the session (after the user authenticated).
void session_lock_unlock();

bool session_lock_active();

// Ids of the lock screen views.
std::vector<int64_t> session_lock_view_ids();

#endif  // PANGOLIN_SESSION_LOCK_H_
