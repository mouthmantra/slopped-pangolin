// SPDX-FileCopyrightText: © 2026 The dahliaOS Authors
// SPDX-License-Identifier: GPL-3.0-only

//! Per-seat state of river_touchpad_gestures_v1: which swipe/pinch finger
//! counts the window manager claimed, and the claimed gesture in progress.

const TouchpadGesturesSeat = @This();

const std = @import("std");
const assert = std.debug.assert;
const wl = @import("wayland").server.wl;
const river = @import("wayland").server.river;

object: ?*river.TouchpadGesturesSeatV1 = null,

swipe_mask: u32 = 0,
pinch_mask: u32 = 0,

/// Gesture currently routed to the window manager. Stays set until the
/// gesture ends even if the object goes away, so that the rest of the gesture
/// isn't sent to a client that never saw it begin.
active: enum { none, swipe, pinch } = .none,

pub fn createObject(
    gseat: *TouchpadGesturesSeat,
    client: *wl.Client,
    version: u32,
    id: u32,
) void {
    assert(gseat.object == null);
    gseat.object = river.TouchpadGesturesSeatV1.create(client, version, id) catch {
        client.postNoMemory();
        return;
    };
    gseat.object.?.setHandler(*TouchpadGesturesSeat, handleRequest, handleDestroy, gseat);
}

pub fn makeInert(gseat: *TouchpadGesturesSeat) void {
    if (gseat.object) |object| {
        object.setHandler(?*anyopaque, handleRequestInert, null, null);
        handleDestroy(object, gseat);
    }
}

fn handleRequestInert(
    object: *river.TouchpadGesturesSeatV1,
    request: river.TouchpadGesturesSeatV1.Request,
    _: ?*anyopaque,
) void {
    if (request == .destroy) object.destroy();
}

fn handleDestroy(_: *river.TouchpadGesturesSeatV1, gseat: *TouchpadGesturesSeat) void {
    gseat.object = null;
    gseat.swipe_mask = 0;
    gseat.pinch_mask = 0;
}

fn handleRequest(
    object: *river.TouchpadGesturesSeatV1,
    request: river.TouchpadGesturesSeatV1.Request,
    gseat: *TouchpadGesturesSeat,
) void {
    assert(gseat.object == object);
    switch (request) {
        .destroy => object.destroy(),
        .set_swipe_fingers => |args| gseat.swipe_mask = args.finger_mask,
        .set_pinch_fingers => |args| gseat.pinch_mask = args.finger_mask,
    }
}

fn claims(mask: u32, fingers: u32) bool {
    return fingers < 32 and (mask >> @intCast(fingers)) & 1 != 0;
}

/// Returns true if the swipe is the window manager's (the event was sent).
pub fn swipeBegin(gseat: *TouchpadGesturesSeat, time: u32, fingers: u32) bool {
    const object = gseat.object orelse return false;
    if (!claims(gseat.swipe_mask, fingers)) return false;
    gseat.active = .swipe;
    object.sendSwipeBegin(time, fingers);
    return true;
}

/// Returns true if the event belongs to a claimed swipe (and was consumed).
pub fn swipeUpdate(gseat: *TouchpadGesturesSeat, time: u32, dx: f64, dy: f64) bool {
    if (gseat.active != .swipe) return false;
    if (gseat.object) |object| object.sendSwipeUpdate(time, .fromDouble(dx), .fromDouble(dy));
    return true;
}

pub fn swipeEnd(gseat: *TouchpadGesturesSeat, time: u32, cancelled: bool) bool {
    if (gseat.active != .swipe) return false;
    gseat.active = .none;
    if (gseat.object) |object| object.sendSwipeEnd(time, @intFromBool(cancelled));
    return true;
}

pub fn pinchBegin(gseat: *TouchpadGesturesSeat, time: u32, fingers: u32) bool {
    const object = gseat.object orelse return false;
    if (!claims(gseat.pinch_mask, fingers)) return false;
    gseat.active = .pinch;
    object.sendPinchBegin(time, fingers);
    return true;
}

pub fn pinchUpdate(
    gseat: *TouchpadGesturesSeat,
    time: u32,
    dx: f64,
    dy: f64,
    scale: f64,
    rotation: f64,
) bool {
    if (gseat.active != .pinch) return false;
    if (gseat.object) |object| {
        object.sendPinchUpdate(time, .fromDouble(dx), .fromDouble(dy), .fromDouble(scale), .fromDouble(rotation));
    }
    return true;
}

pub fn pinchEnd(gseat: *TouchpadGesturesSeat, time: u32, cancelled: bool) bool {
    if (gseat.active != .pinch) return false;
    gseat.active = .none;
    if (gseat.object) |object| object.sendPinchEnd(time, @intFromBool(cancelled));
    return true;
}
