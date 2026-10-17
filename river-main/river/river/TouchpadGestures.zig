// SPDX-FileCopyrightText: © 2026 The dahliaOS Authors
// SPDX-License-Identifier: GPL-3.0-only

//! river_touchpad_gestures_v1 global: lets the window manager claim touchpad
//! swipe/pinch gestures (downstream extension for the Pangolin desktop).

const TouchpadGestures = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const river = @import("wayland").server.river;

const server = &@import("main.zig").server;

const Seat = @import("Seat.zig");

const log = std.log.scoped(.wm);

global: *wl.Global,

server_destroy: wl.Listener(*wl.Server) = .init(handleServerDestroy),

pub fn init(gestures: *TouchpadGestures) !void {
    gestures.* = .{
        .global = try wl.Global.create(server.wl_server, river.TouchpadGesturesV1, 1, ?*anyopaque, null, bind),
    };
    server.wl_server.addDestroyListener(&gestures.server_destroy);
}

fn handleServerDestroy(listener: *wl.Listener(*wl.Server), _: *wl.Server) void {
    const gestures: *TouchpadGestures = @fieldParentPtr("server_destroy", listener);

    gestures.global.destroy();
}

fn bind(client: *wl.Client, _: ?*anyopaque, version: u32, id: u32) void {
    const object = river.TouchpadGesturesV1.create(client, version, id) catch {
        client.postNoMemory();
        log.err("out of memory", .{});
        return;
    };

    object.setHandler(?*anyopaque, handleRequest, null, null);
}

fn handleRequest(
    object: *river.TouchpadGesturesV1,
    request: river.TouchpadGesturesV1.Request,
    _: ?*anyopaque,
) void {
    switch (request) {
        .destroy => object.destroy(),
        .get_seat => |args| {
            // river_seat_v1 objects are made inert when the active window
            // manager goes away, so only the active window manager gets here.
            const seat_data = args.seat.getUserData() orelse return;
            const seat: *Seat = @ptrCast(@alignCast(seat_data));
            if (seat.touchpad_gestures.object != null) {
                object.postError(
                    .object_already_created,
                    "river_touchpad_gestures_seat_v1 already created",
                );
                return;
            }
            seat.touchpad_gestures.createObject(object.getClient(), object.getVersion(), args.id);
        },
    }
}
