// SPDX-FileCopyrightText: © 2021 The River Developers
// SPDX-License-Identifier: GPL-3.0-only

const LockManager = @This();

const std = @import("std");
const assert = std.debug.assert;

const build_options = @import("build_options");

const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const server = &@import("main.zig").server;
const util = @import("util.zig");

const LockSurface = @import("LockSurface.zig");
const Output = @import("Output.zig");

const log = std.log.scoped(.lock);

const fade_ms = 350;

const FadeNode = struct {
    output: *wlr.Output,
    scene_buffer: *wlr.SceneBuffer,
};

wlr_manager: *wlr.SessionLockManagerV1,

state: enum {
    /// No lock request has been made and the session is unlocked.
    unlocked,
    /// A lock request has been made and river is waiting for all outputs to have
    /// rendered a lock surface before sending the locked event.
    waiting_for_lock_surfaces,
    /// A lock request has been made but waiting for a lock surface to be rendered
    /// on all outputs timed out. Now river is waiting only for all outputs to at
    /// least be blanked before sending the locked event.
    waiting_for_blank,
    /// All outputs are either blanked or have a lock surface rendered and the
    /// locked event has been sent.
    locked,
} = .unlocked,
lock: ?*wlr.SessionLockV1 = null,

/// Limit on how long the locked event will be delayed to wait for
/// lock surfaces to be created and rendered. If this times out, then
/// the locked event will be sent immediately after all outputs have
/// been blanked.
lock_surfaces_timer: *wl.EventSource,

/// Pangolin: on unlock the lock screen fades away over the desktop. The
/// client destroys its lock surfaces right after unlocking: their last
/// frames are kept (scene buffers hold the buffers) for the fade.
fade_tree: ?*wlr.SceneTree = null,
fade_nodes: std.ArrayList(FadeNode) = .empty,
fade_start: ?u32 = null,

new_lock: wl.Listener(*wlr.SessionLockV1) = .init(handleLock),
unlock: wl.Listener(void) = .init(handleUnlock),
destroy: wl.Listener(void) = .init(handleDestroy),
new_surface: wl.Listener(*wlr.SessionLockSurfaceV1) = .init(handleSurface),

pub fn init(manager: *LockManager) !void {
    const event_loop = server.wl_server.getEventLoop();
    const timer = try event_loop.addTimer(*LockManager, handleLockSurfacesTimeout, manager);
    errdefer timer.remove();

    manager.* = .{
        .wlr_manager = try wlr.SessionLockManagerV1.create(server.wl_server),
        .lock_surfaces_timer = timer,
    };

    manager.wlr_manager.events.new_lock.add(&manager.new_lock);
}

pub fn deinit(manager: *LockManager) void {
    // deinit() should only be called after wl.Server.destroyClients()
    assert(manager.lock == null);

    manager.lock_surfaces_timer.remove();

    manager.new_lock.link.remove();
    // The fade's nodes go with the scene.
    manager.fade_nodes.deinit(util.gpa);
}

fn handleLock(listener: *wl.Listener(*wlr.SessionLockV1), lock: *wlr.SessionLockV1) void {
    const manager: *LockManager = @fieldParentPtr("new_lock", listener);

    log.debug("session lock client made lock request", .{});

    if (manager.lock != null) {
        log.info("denying new session lock client, an active one already exists", .{});
        lock.destroy();
        return;
    }

    manager.lock = lock;

    if (manager.state == .unlocked) {
        manager.state = .waiting_for_lock_surfaces;

        assert(!server.scene.locked_tree.node.enabled);
        server.scene.locked_tree.node.setEnabled(true);

        manager.lock_surfaces_timer.timerUpdate(200) catch {
            log.err("error setting lock surfaces timer, imperfect frames may be shown", .{});
            manager.state = .waiting_for_blank;
            // This call is necessary in the case that all outputs in the layout are disabled.
            manager.maybeLock();
        };

        {
            var it = server.input_manager.seats.iterator(.forward);
            while (it.next()) |seat| {
                seat.focus(.none);
            }
        }
    } else {
        if (manager.state == .locked) {
            lock.sendLocked();
        }

        log.info("new session lock client given control of already locked session", .{});
    }

    lock.events.new_surface.add(&manager.new_surface);
    lock.events.unlock.add(&manager.unlock);
    lock.events.destroy.add(&manager.destroy);
}

fn handleLockSurfacesTimeout(manager: *LockManager) c_int {
    log.err("waiting for lock surfaces timed out, imperfect frames may be shown", .{});
    manager.waitForBlank();
    return 0;
}

fn waitForBlank(manager: *LockManager) void {
    assert(manager.state == .waiting_for_lock_surfaces);
    manager.state = .waiting_for_blank;

    server.scene.normal_tree.node.setEnabled(false);

    // This call is necessary in the case that all outputs in the layout are disabled.
    manager.maybeLock();
}

pub fn maybeLock(manager: *LockManager) void {
    var all_outputs_blanked = true;
    var all_outputs_rendered_lock_surface = true;
    {
        var it = server.om.outputs.iterator(.forward);
        while (it.next()) |output| {
            const wlr_output = output.wlr_output orelse continue;
            if (!wlr_output.enabled) continue;

            switch (output.lock_render_state) {
                .pending_unlock, .unlocked, .pending_blank, .pending_lock_surface => {
                    all_outputs_blanked = false;
                    all_outputs_rendered_lock_surface = false;
                },
                .blanked => {
                    all_outputs_rendered_lock_surface = false;
                },
                .lock_surface => {},
            }
        }
    }

    switch (manager.state) {
        .waiting_for_lock_surfaces => if (all_outputs_rendered_lock_surface) {
            manager.sendLocked();
            server.scene.normal_tree.node.setEnabled(false);
            manager.lock_surfaces_timer.timerUpdate(0) catch {};
        },
        .waiting_for_blank => if (all_outputs_blanked) {
            manager.sendLocked();
        },
        .unlocked, .locked => unreachable,
    }
}

fn sendLocked(manager: *LockManager) void {
    log.info("session locked", .{});
    // The lock client may have been destroyed, for example due to a protocol error.
    if (manager.lock) |lock| lock.sendLocked();
    manager.state = .locked;
    server.wm.dirtyWindowing();
}

fn handleUnlock(listener: *wl.Listener(void)) void {
    const manager: *LockManager = @fieldParentPtr("unlock", listener);

    manager.state = .unlocked;

    log.info("session unlocked", .{});
    manager.startFade();

    assert(!server.scene.normal_tree.node.enabled);
    server.scene.normal_tree.node.setEnabled(true);

    assert(server.scene.locked_tree.node.enabled);
    server.scene.locked_tree.node.setEnabled(false);

    {
        var it = server.input_manager.seats.iterator(.forward);
        while (it.next()) |seat| {
            seat.focus(.none);
        }
    }

    handleDestroy(&manager.destroy);

    server.wm.dirtyWindowing();
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const manager: *LockManager = @fieldParentPtr("destroy", listener);

    log.debug("ext_session_lock_v1 destroyed", .{});

    manager.new_surface.link.remove();
    manager.unlock.link.remove();
    manager.destroy.link.remove();

    manager.lock = null;
    if (manager.state == .waiting_for_lock_surfaces) {
        manager.lock_surfaces_timer.timerUpdate(0) catch {};
        manager.waitForBlank();
    }
}

fn handleSurface(
    listener: *wl.Listener(*wlr.SessionLockSurfaceV1),
    wlr_lock_surface: *wlr.SessionLockSurfaceV1,
) void {
    const manager: *LockManager = @fieldParentPtr("new_surface", listener);

    log.debug("new ext_session_lock_surface_v1 created", .{});

    assert(manager.state != .unlocked);
    assert(manager.lock != null);

    LockSurface.create(wlr_lock_surface, manager.lock.?) catch {
        log.err("out of memory", .{});
        wlr_lock_surface.resource.postNoMemory();
    };
}

fn startFade(manager: *LockManager) void {
    manager.clearFade();
    const tree = server.scene.wlr_scene.tree.createSceneTree() catch return;
    tree.node.raiseToTop();
    manager.fade_tree = tree;
    var it = server.om.outputs.iterator(.forward);
    while (it.next()) |output| {
        const wlr_output = output.wlr_output orelse continue;
        const lock_surface = manager.lockSurfaceFromOutput(output) orelse continue;
        const client_buffer = lock_surface.wlr_lock_surface.surface.buffer orelse continue;
        var box: wlr.Box = undefined;
        server.om.output_layout.getBox(wlr_output, &box);
        if (box.width <= 0 or box.height <= 0) continue;
        const scene_buffer = tree.createSceneBuffer(&client_buffer.base) catch continue;
        scene_buffer.point_accepts_input = rejectInput;
        scene_buffer.node.setPosition(box.x, box.y);
        scene_buffer.setDestSize(box.width, box.height);
        manager.fade_nodes.append(util.gpa, .{ .output = wlr_output, .scene_buffer = scene_buffer }) catch {
            scene_buffer.node.destroy();
            continue;
        };
        wlr_output.scheduleFrame();
    }
}

fn clearFade(manager: *LockManager) void {
    // The tree takes its scene buffers (and their buffers) with it.
    if (manager.fade_tree) |tree| tree.node.destroy();
    manager.fade_tree = null;
    manager.fade_nodes.clearRetainingCapacity();
    manager.fade_start = null;
}

/// Right before an output renders: the unlock fade's next step.
pub fn beforeFrame(manager: *LockManager) void {
    if (manager.fade_nodes.items.len == 0) return;
    const now = util.msecTimestamp();
    const start = manager.fade_start orelse blk: {
        manager.fade_start = now;
        break :blk now;
    };
    const t = @min(1.0, @as(f32, @floatFromInt(now -% start)) / fade_ms);
    if (t >= 1) {
        manager.clearFade();
        return;
    }
    // Smoothstep out.
    const opacity = 1 - t * t * (3 - 2 * t);
    for (manager.fade_nodes.items) |node| {
        node.scene_buffer.setOpacity(opacity);
        node.output.scheduleFrame();
    }
}

fn rejectInput(_: *wlr.SceneBuffer, _: *f64, _: *f64) callconv(.c) bool {
    return false;
}

pub fn lockSurfaceFromOutput(manager: *LockManager, output: *Output) ?*LockSurface {
    const lock = manager.lock orelse return null;

    var it = lock.surfaces.iterator(.forward);
    while (it.next()) |wlr_lock_surface| {
        const lock_surface: *LockSurface = @ptrCast(@alignCast(wlr_lock_surface.data));
        if (output == lock_surface.getOutput()) {
            return lock_surface;
        }
    }

    return null;
}
