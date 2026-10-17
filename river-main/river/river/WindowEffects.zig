// SPDX-FileCopyrightText: © 2026 The dahliaOS Authors
// SPDX-License-Identifier: GPL-3.0-only

//! river_window_effects_v1 global: lets the window manager draw animated,
//! scaled and translucent mirrors of windows (downstream extension for the
//! Pangolin desktop).
//!
//! A mirror is a set of scene buffers that reference the buffers of a window
//! (like the saved surfaces of the transaction system), so creating and
//! animating one copies no pixels. Animations are advanced by river right
//! before each output frame.

const WindowEffects = @This();

const std = @import("std");
const assert = std.debug.assert;
const math = std.math;
const posix = std.posix;
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;
const river = @import("wayland").server.river;

const server = &@import("main.zig").server;
const util = @import("util.zig");

const Output = @import("Output.zig");
const Window = @import("Window.zig");

const log = std.log.scoped(.wm);

global: *wl.Global,

bindings: wl.list.Head(Binding, .link),
mirrors: wl.list.Head(Mirror, .link),

server_destroy: wl.Listener(*wl.Server) = .init(handleServerDestroy),

const Binding = struct {
    object: *river.WindowEffectsV1,
    closing_mirrors: bool = false,
    link: wl.list.Link,
};

pub fn init(effects: *WindowEffects) !void {
    effects.* = .{
        .global = try wl.Global.create(server.wl_server, river.WindowEffectsV1, 1, ?*anyopaque, null, bind),
        .bindings = undefined,
        .mirrors = undefined,
    };
    effects.bindings.init();
    effects.mirrors.init();
    server.wl_server.addDestroyListener(&effects.server_destroy);
}

fn handleServerDestroy(listener: *wl.Listener(*wl.Server), _: *wl.Server) void {
    const effects: *WindowEffects = @fieldParentPtr("server_destroy", listener);

    effects.global.destroy();
}

fn bind(client: *wl.Client, _: ?*anyopaque, version: u32, id: u32) void {
    const object = river.WindowEffectsV1.create(client, version, id) catch {
        client.postNoMemory();
        log.err("out of memory", .{});
        return;
    };
    const binding = util.gpa.create(Binding) catch {
        object.postNoMemory();
        log.err("out of memory", .{});
        return;
    };
    binding.* = .{ .object = object, .link = undefined };
    server.window_effects.bindings.append(binding);

    object.setHandler(*Binding, handleRequest, handleBindingDestroy, binding);
}

fn handleBindingDestroy(_: *river.WindowEffectsV1, binding: *Binding) void {
    binding.link.remove();
    util.gpa.destroy(binding);
}

fn handleRequest(
    object: *river.WindowEffectsV1,
    request: river.WindowEffectsV1.Request,
    binding: *Binding,
) void {
    switch (request) {
        .destroy => object.destroy(),
        .get_mirror => |args| {
            const mirror_v1 = river.WindowMirrorV1.create(
                object.getClient(),
                object.getVersion(),
                args.id,
            ) catch {
                object.postNoMemory();
                log.err("out of memory", .{});
                return;
            };
            // Inert river_window_v1 objects have no user data.
            const window: ?*Window = if (args.window.getUserData()) |data|
                @ptrCast(@alignCast(data))
            else
                null;
            Mirror.create(mirror_v1, window, true) catch {
                mirror_v1.postNoMemory();
                log.err("out of memory", .{});
                return;
            };
        },
        .set_closing_mirrors => |args| binding.closing_mirrors = args.enabled != 0,
    }
}

/// Called right after the window saved its surfaces for the close.
pub fn windowUnmapped(effects: *WindowEffects, window: *Window) void {
    const window_v1 = window.object orelse return;
    var it = effects.bindings.iterator(.forward);
    while (it.next()) |binding| {
        if (!binding.closing_mirrors) continue;
        if (binding.object.getClient() != window_v1.getClient()) continue;

        const mirror_v1 = river.WindowMirrorV1.create(
            binding.object.getClient(),
            binding.object.getVersion(),
            0,
        ) catch {
            log.err("out of memory", .{});
            continue;
        };
        Mirror.create(mirror_v1, window, false) catch {
            mirror_v1.destroy();
            log.err("out of memory", .{});
            continue;
        };
        binding.object.sendClosingMirror(
            mirror_v1,
            window_v1,
            window.box.x,
            window.box.y,
            window.box.width,
            window.box.height,
        );
    }
}

/// Whether an animated mirror of the window covers it: the window manager is
/// animating it (e.g. into a new size), so there is no point holding every
/// other window back until it draws its new size.
pub fn coversWindow(effects: *WindowEffects, window: *Window) bool {
    var it = effects.mirrors.iterator(.forward);
    while (it.next()) |mirror| {
        const origin = mirror.origin orelse continue;
        if (origin.get() != window) continue;
        if (mirror.visible() and mirror.current.opacity > 0.5) return true;
    }
    return false;
}

/// Called when a window commits, so that mirrors following it are redrawn
/// even if the window itself is hidden.
pub fn windowCommitted(effects: *WindowEffects, window: *Window) void {
    var it = effects.mirrors.iterator(.forward);
    while (it.next()) |mirror| {
        if (mirror.source) |source| {
            if (source.get() == window and mirror.tree.node.enabled) {
                scheduleFrames();
                return;
            }
        }
    }
}

/// Advance animations and follow window content, right before an output
/// renders a frame.
pub fn beforeFrame(effects: *WindowEffects) void {
    if (effects.mirrors.empty()) return;

    const now = nanoTimestamp();
    var animating = false;
    var it = effects.mirrors.safeIterator(.forward);
    while (it.next()) |mirror| {
        if (mirror.source) |source| {
            if (source.get()) |window| {
                if (mirror.visible()) mirror.sync(window);
            } else {
                mirror.source = null;
            }
        }
        if (mirror.tick(now)) animating = true;
    }
    if (animating) scheduleFrames();
}

/// Send frame callbacks to the windows behind visible live mirrors drawn on
/// the output, which may be hidden.
pub fn afterFrame(effects: *WindowEffects, output: *Output, now: *const posix.timespec) void {
    const scene_output = output.scene_output orelse return;
    var it = effects.mirrors.iterator(.forward);
    while (it.next()) |mirror| {
        const source = mirror.source orelse continue;
        const window = source.get() orelse continue;
        if (!mirror.visible()) continue;
        const on_output = for (mirror.nodes.items) |node| {
            if (node.buffer.primary_output == scene_output) break true;
        } else false;
        if (!on_output) continue;
        sendFrameDoneTree(window.tree, now);
    }
}

fn sendFrameDoneTree(tree: *wlr.SceneTree, now: *const posix.timespec) void {
    var it = tree.children.iterator(.forward);
    while (it.next()) |node| {
        if (!node.enabled) continue;
        switch (node.type) {
            .tree => sendFrameDoneTree(wlr.SceneTree.fromNode(node), now),
            .buffer => {
                const scene_buffer = wlr.SceneBuffer.fromNode(node);
                if (wlr.SceneSurface.tryFromBuffer(scene_buffer)) |scene_surface| {
                    scene_surface.surface.sendFrameDone(now);
                }
            },
            .rect => {},
        }
    }
}

fn scheduleFrames() void {
    var it = server.om.outputs.iterator(.forward);
    while (it.next()) |output| {
        if (output.wlr_output) |wlr_output| {
            if (wlr_output.enabled) wlr_output.scheduleFrame();
        }
    }
}

fn nanoTimestamp() i128 {
    const now = util.timestamp();
    return @as(i128, now.sec) * std.time.ns_per_s + now.nsec;
}

const State = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    opacity: f64,

    fn lerp(a: State, b: State, t: f64) State {
        return .{
            .x = a.x + (b.x - a.x) * t,
            .y = a.y + (b.y - a.y) * t,
            .width = a.width + (b.width - a.width) * t,
            .height = a.height + (b.height - a.height) * t,
            .opacity = a.opacity + (b.opacity - a.opacity) * t,
        };
    }
};

/// A scene buffer of the mirror and the geometry of the buffer it mirrors,
/// relative to the window.
const Node = struct {
    buffer: *wlr.SceneBuffer,
    source: ?*wlr.Buffer = null,
    seq: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
};

const Mirror = struct {
    object: *river.WindowMirrorV1,
    link: wl.list.Link,
    tree: *wlr.SceneTree,

    /// The window followed, null once frozen.
    source: ?Window.Ref,
    /// The window mirrored, frozen or not.
    origin: ?Window.Ref,
    /// The window size the node geometry is relative to.
    source_width: i32 = 1,
    source_height: i32 = 1,

    nodes: std.ArrayList(Node) = .empty,

    current: State,
    from: State,
    to: State,
    start: i128 = 0,
    duration: i128 = 0,
    curve: [4]f64 = .{ 0, 0, 1, 1 },
    animating: bool = false,

    fn create(object: *river.WindowMirrorV1, window: ?*Window, live: bool) !void {
        const tree = try server.scene.layers.effects.createSceneTree();
        errdefer tree.node.destroy();

        const mirror = try util.gpa.create(Mirror);
        errdefer util.gpa.destroy(mirror);

        const state: State = if (window) |w| .{
            .x = @floatFromInt(w.box.x),
            .y = @floatFromInt(w.box.y),
            .width = @floatFromInt(w.box.width),
            .height = @floatFromInt(w.box.height),
            .opacity = 0,
        } else .{ .x = 0, .y = 0, .width = 0, .height = 0, .opacity = 0 };

        mirror.* = .{
            .object = object,
            .link = undefined,
            .tree = tree,
            .source = if (live and window != null) window.?.ref else null,
            .origin = if (window) |w| w.ref else null,
            .current = state,
            .from = state,
            .to = state,
        };
        server.window_effects.mirrors.append(mirror);
        object.setHandler(*Mirror, handleMirrorRequest, handleMirrorDestroy, mirror);

        if (window) |w| mirror.sync(w);
        mirror.apply();
    }

    fn visible(mirror: *const Mirror) bool {
        return mirror.current.opacity > 0.001 and
            mirror.current.width >= 1 and mirror.current.height >= 1;
    }

    /// Mirror the current buffers of the window.
    fn sync(mirror: *Mirror, window: *Window) void {
        mirror.source_width = @max(1, window.box.width);
        mirror.source_height = @max(1, window.box.height);

        var index: usize = 0;
        // The root tree of the window is disabled while the window is hidden,
        // its children are not.
        mirror.collect(window.tree, 0, 0, &index);
        while (mirror.nodes.items.len > index) {
            const node = mirror.nodes.pop().?;
            node.buffer.node.destroy();
        }
        mirror.apply();
    }

    fn collect(mirror: *Mirror, tree: *wlr.SceneTree, x: i32, y: i32, index: *usize) void {
        var it = tree.children.iterator(.forward);
        while (it.next()) |node| {
            if (!node.enabled) continue;
            const nx = x + node.x;
            const ny = y + node.y;
            switch (node.type) {
                .tree => mirror.collect(wlr.SceneTree.fromNode(node), nx, ny, index),
                .buffer => mirror.mirrorBuffer(wlr.SceneBuffer.fromNode(node), nx, ny, index),
                .rect => {},
            }
        }
    }

    fn mirrorBuffer(mirror: *Mirror, src: *wlr.SceneBuffer, x: i32, y: i32, index: *usize) void {
        const buffer = src.buffer orelse return;
        const width = if (src.dst_width > 0) src.dst_width else buffer.width;
        const height = if (src.dst_height > 0) src.dst_height else buffer.height;
        if (width <= 0 or height <= 0) return;

        if (index.* == mirror.nodes.items.len) {
            const scene_buffer = mirror.tree.createSceneBuffer(null) catch {
                log.err("out of memory", .{});
                return;
            };
            scene_buffer.point_accepts_input = rejectInput;
            mirror.nodes.append(util.gpa, .{ .buffer = scene_buffer }) catch {
                scene_buffer.node.destroy();
                log.err("out of memory", .{});
                return;
            };
        }
        const node = &mirror.nodes.items[index.*];
        index.* += 1;

        // shm buffers may be updated in place: compare commit sequences too.
        const seq: u32 = if (wlr.SceneSurface.tryFromBuffer(src)) |scene_surface|
            scene_surface.surface.current.seq
        else
            0;
        if (node.source != buffer or node.seq != seq) {
            node.buffer.setBuffer(buffer);
            node.source = buffer;
            node.seq = seq;
        }
        node.buffer.setSourceBox(&src.src_box);
        node.buffer.setTransform(src.transform);
        node.x = x;
        node.y = y;
        node.width = width;
        node.height = height;
    }

    /// Place the scene buffers for the current state.
    fn apply(mirror: *Mirror) void {
        const visible_ = mirror.visible();
        mirror.tree.node.setEnabled(visible_);
        if (!visible_) return;

        const s = mirror.current;
        const kx = s.width / @as(f64, @floatFromInt(mirror.source_width));
        const ky = s.height / @as(f64, @floatFromInt(mirror.source_height));
        const opacity: f32 = @floatCast(math.clamp(s.opacity, 0, 1));
        for (mirror.nodes.items) |node| {
            // Round edges rather than sizes so adjacent buffers never leave gaps.
            const x0: i32 = @intFromFloat(@round(s.x + @as(f64, @floatFromInt(node.x)) * kx));
            const y0: i32 = @intFromFloat(@round(s.y + @as(f64, @floatFromInt(node.y)) * ky));
            const x1: i32 = @intFromFloat(@round(s.x + @as(f64, @floatFromInt(node.x + node.width)) * kx));
            const y1: i32 = @intFromFloat(@round(s.y + @as(f64, @floatFromInt(node.y + node.height)) * ky));
            node.buffer.node.setPosition(x0, y0);
            node.buffer.setDestSize(@max(1, x1 - x0), @max(1, y1 - y0));
            node.buffer.setOpacity(opacity);
        }
    }

    /// Returns true while the animation is running.
    fn tick(mirror: *Mirror, now: i128) bool {
        if (!mirror.animating) return false;
        const elapsed = now - mirror.start;
        const t: f64 = if (mirror.duration <= 0)
            1
        else
            math.clamp(@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(mirror.duration)), 0, 1);
        if (t >= 1) {
            mirror.current = mirror.to;
            mirror.animating = false;
            mirror.apply();
            mirror.object.sendDone();
            return false;
        }
        const c = mirror.curve;
        mirror.current = State.lerp(mirror.from, mirror.to, cubicBezier(c[0], c[1], c[2], c[3], t));
        mirror.apply();
        return true;
    }
};

fn rejectInput(_: *wlr.SceneBuffer, _: *f64, _: *f64) callconv(.c) bool {
    return false;
}

fn handleMirrorDestroy(_: *river.WindowMirrorV1, mirror: *Mirror) void {
    mirror.link.remove();
    mirror.tree.node.destroy();
    mirror.nodes.deinit(util.gpa);
    util.gpa.destroy(mirror);
}

fn handleMirrorRequest(
    object: *river.WindowMirrorV1,
    request: river.WindowMirrorV1.Request,
    mirror: *Mirror,
) void {
    switch (request) {
        .destroy => object.destroy(),
        .freeze => mirror.source = null,
        .place_top => mirror.tree.node.raiseToTop(),
        .animate => |args| {
            const target: State = .{
                .x = @floatFromInt(args.x),
                .y = @floatFromInt(args.y),
                .width = @floatFromInt(@max(0, args.width)),
                .height = @floatFromInt(@max(0, args.height)),
                .opacity = math.clamp(args.opacity.toDouble(), 0, 1),
            };
            if (args.duration == 0) {
                mirror.animating = false;
                mirror.current = target;
                mirror.from = target;
                mirror.to = target;
                // Pick up content the window committed while invisible.
                if (mirror.source) |source| {
                    if (source.get()) |window| mirror.sync(window);
                }
                mirror.apply();
                return;
            }
            mirror.from = mirror.current;
            mirror.to = target;
            mirror.start = nanoTimestamp();
            mirror.duration = @as(i128, args.duration) * std.time.ns_per_ms;
            mirror.curve = .{
                math.clamp(args.x1.toDouble(), 0, 1),
                args.y1.toDouble(),
                math.clamp(args.x2.toDouble(), 0, 1),
                args.y2.toDouble(),
            };
            mirror.animating = true;
            scheduleFrames();
        },
    }
}

/// Evaluates the CSS cubic-bezier(x1, y1, x2, y2) timing function at t.
fn cubicBezier(x1: f64, y1: f64, x2: f64, y2: f64, t: f64) f64 {
    if (t <= 0) return 0;
    if (t >= 1) return 1;

    const cx = 3 * x1;
    const bx = 3 * (x2 - x1) - cx;
    const ax = 1 - cx - bx;
    const cy = 3 * y1;
    const by = 3 * (y2 - y1) - cy;
    const ay = 1 - cy - by;

    const sampleX = struct {
        fn f(a: f64, b: f64, c: f64, u: f64) f64 {
            return ((a * u + b) * u + c) * u;
        }
    }.f;

    // Newton's method, falling back to bisection.
    var u = t;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const x = sampleX(ax, bx, cx, u) - t;
        if (@abs(x) < 1e-6) return sampleX(ay, by, cy, u);
        const d = (3 * ax * u + 2 * bx) * u + cx;
        if (@abs(d) < 1e-6) break;
        u -= x / d;
    }
    var lo: f64 = 0;
    var hi: f64 = 1;
    u = t;
    i = 0;
    while (i < 32) : (i += 1) {
        const x = sampleX(ax, bx, cx, u);
        if (@abs(x - t) < 1e-6) break;
        if (x < t) lo = u else hi = u;
        u = (lo + hi) / 2;
    }
    return sampleX(ay, by, cy, u);
}
