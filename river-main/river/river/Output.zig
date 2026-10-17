// SPDX-FileCopyrightText: © 2020 The River Developers
// SPDX-License-Identifier: GPL-3.0-only

const Output = @This();

const std = @import("std");
const assert = std.debug.assert;
const math = std.math;
const mem = std.mem;
const posix = std.posix;
const fmt = std.fmt;
const wlr = @import("wlroots");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const zwlr = wayland.server.zwlr;
const river = wayland.server.river;

const server = &@import("main.zig").server;
const util = @import("util.zig");

const LayerShellOutput = @import("LayerShellOutput.zig");
const LockSurface = @import("LockSurface.zig");
const SceneNodeData = @import("SceneNodeData.zig");
const Window = @import("Window.zig");

const log = std.log.scoped(.output);

pub const State = struct {
    state: enum {
        /// Powered on and exposed to the window manager
        enabled,
        /// Powered off and exposed to the window manager
        disabled_soft,
        /// Powered off and hidden from the window manager
        disabled_hard,
        /// Corresponding hardware no longer present
        destroying,
    },
    /// Logical coordinate space
    x: i32,
    /// Logical coordinate space
    y: i32,
    /// The width/height of modes is in physical pixels, not in the
    /// compositors logical coordinate space.
    mode: union(enum) {
        standard: *wlr.Output.Mode,
        custom: struct {
            width: i32,
            height: i32,
            refresh: i32,
        },
        /// Used before the initial modeset and after the wlr_output is destroyed.
        none,
    },
    scale: f32,
    transform: wl.Output.Transform,
    adaptive_sync: bool,
    auto_layout: bool,

    capture_session_count: u32,

    pub fn fromHeadState(state: *const wlr.OutputHeadV1.State) State {
        assert(state.enabled);
        return .{
            .state = .enabled,
            .mode = blk: {
                if (state.mode) |mode| {
                    break :blk .{ .standard = mode };
                } else {
                    break :blk .{ .custom = .{
                        .width = state.custom_mode.width,
                        .height = state.custom_mode.height,
                        .refresh = state.custom_mode.refresh,
                    } };
                }
            },
            .x = state.x,
            .y = state.y,
            // Round to nearest 1/120 to ensure the scale is exactly represented
            // in the fractional-scale-v1 protocol.
            .scale = wholeLogicalScale(
                @round(state.scale * 120) / 120,
                if (state.mode) |mode| mode.width else state.custom_mode.width,
                if (state.mode) |mode| mode.height else state.custom_mode.height,
            ),
            .transform = state.transform,
            .adaptive_sync = state.adaptive_sync_enabled,
            .auto_layout = false,
            .capture_session_count = 0,
        };
    }

    /// Pangolin: a scale that divides the mode into whole logical pixels (e.g.
    /// 4/3 for 3840x2160 -> 2880x1620) is nudged so that dividing in f32, as
    /// wlroots does (truncating), lands exactly on them rather than one pixel
    /// short.
    fn wholeLogicalScale(scale: f32, width: i32, height: i32) f32 {
        if (width <= 0 or height <= 0 or scale <= 0) return scale;
        const w: f32 = @floatFromInt(width);
        const h: f32 = @floatFromInt(height);
        const logical_w = @round(w / scale);
        const logical_h = @round(h / scale);
        if (logical_w < 1 or logical_h < 1) return scale;
        if (@abs(w / scale - logical_w) > 0.05 or @abs(h / scale - logical_h) > 0.05) return scale;
        var snapped = w / logical_w;
        var guard: usize = 0;
        while ((@floor(w / snapped) < logical_w or @floor(h / snapped) < logical_h) and guard < 8) : (guard += 1) {
            snapped = math.nextAfter(f32, snapped, 0);
        }
        return snapped;
    }

    /// Width/height in the logical coordinate space
    pub fn dimensions(state: *const State) struct { u31, u31 } {
        var w: i32, var h: i32 = switch (state.mode) {
            .standard => |mode| .{ mode.width, mode.height },
            .custom => |mode| .{ mode.width, mode.height },
            .none => .{ 0, 0 },
        };
        if (@mod(@intFromEnum(state.transform), 2) != 0) {
            mem.swap(i32, &w, &h);
        }
        return .{
            @intFromFloat(@as(f32, @floatFromInt(w)) / state.scale),
            @intFromFloat(@as(f32, @floatFromInt(h)) / state.scale),
        };
    }

    pub fn box(state: *const State) wlr.Box {
        const w, const h = state.dimensions();
        return .{ .x = state.x, .y = state.y, .width = w, .height = h };
    }

    pub fn applyNoModeset(state: *const State, wlr_state: *wlr.Output.State) void {
        wlr_state.setScale(state.scale);
        wlr_state.setTransform(state.transform);
    }

    pub fn applyModeset(state: *const State, wlr_state: *wlr.Output.State) void {
        const enabled = state.state == .enabled;
        wlr_state.setEnabled(enabled);
        if (!enabled) return;
        state.applyNoModeset(wlr_state);
        switch (state.mode) {
            .standard => |mode| wlr_state.setMode(mode),
            .custom => |mode| wlr_state.setCustomMode(mode.width, mode.height, mode.refresh),
            .none => {},
        }
        wlr_state.setAdaptiveSyncEnabled(state.adaptive_sync);
    }
};

const RenderingState = struct {
    tearing: bool,
    const init: RenderingState = .{
        .tearing = false,
    };
};

/// Set to null when the wlr_output is destroyed.
wlr_output: ?*wlr.Output,
scene_output: ?*wlr.SceneOutput,

object: ?*river.OutputV1 = null,
layer_shell: LayerShellOutput = .{},

/// Tracks the currently presented frame on the output as it pertains to ext-session-lock.
/// The output is initially considered blanked:
/// If using the DRM backend it will be blanked with the initial modeset.
/// If using the Wayland or X11 backend nothing will be visible until the first frame is rendered.
lock_render_state: enum {
    /// Submitted an unlocked buffer but the buffer has not yet been presented.
    pending_unlock,
    /// Normal, "unlocked" content may be visible.
    unlocked,
    /// Submitted a blank buffer but the buffer has not yet been presented.
    /// Normal, "unlocked" content may be visible.
    pending_blank,
    /// A blank buffer has been presented.
    blanked,
    /// Submitted the lock surface buffer but the buffer has not yet been presented.
    /// Normal, "unlocked" content may be visible.
    pending_lock_surface,
    /// The lock surface buffer has been presented.
    lock_surface,
} = .blanked,

/// Root.outputs
link: wl.list.Link,

/// State to be sent to the wm in the next manage sequence.
scheduled: State,
/// State sent to the wm in the latest manage sequence.
sent: State,
link_sent: wl.list.Link,
sent_wl_output: bool = false,
/// Rendering state requested by the window manager.
rendering_requested: RenderingState = .init,
/// State applied to the wlr_output and rendered.
current: State,
rendering_current: RenderingState = .init,

destroy: wl.Listener(*wlr.Output) = .init(handleDestroy),
request_state: wl.Listener(*wlr.Output.event.RequestState) = .init(handleRequestState),
frame: wl.Listener(*wlr.Output) = .init(handleFrame),
present: wl.Listener(*wlr.Output.event.Present) = .init(handlePresent),

/// Pangolin: retries a frame the kernel refused. i915 answers EBUSY now and
/// then right after a page flip; without a retry the screen waits for the
/// next change, so a moving pointer stutters.
retry_timer: ?*wl.EventSource = null,
retries: u8 = 0,

pub fn create(wlr_output: *wlr.Output) !void {
    const output = try util.gpa.create(Output);
    errdefer util.gpa.destroy(output);

    {
        const title = try fmt.allocPrintSentinel(util.gpa, "river - {s}", .{wlr_output.name}, 0);
        defer util.gpa.free(title);
        if (wlr_output.isWl()) {
            wlr_output.wlSetAppId("river");
            wlr_output.wlSetTitle(title);
        } else if (wlr.config.has_x11_backend and wlr_output.isX11()) {
            wlr_output.x11SetTitle(title);
        }
    }

    if (!wlr_output.initRender(server.allocator, server.renderer)) return error.InitRenderFailed;

    const initial: State = .{
        .state = .disabled_hard,
        .x = 0,
        .y = 0,
        .mode = .none,
        .scale = 1,
        .transform = .normal,
        .adaptive_sync = wlr_output.adaptive_sync_status == .enabled,
        .auto_layout = true,
        .capture_session_count = 0,
    };
    output.* = .{
        .wlr_output = wlr_output,
        .scene_output = null,
        .scheduled = initial,
        .sent = initial,
        .current = initial,
        .link = undefined,
        .link_sent = undefined,
    };
    wlr_output.data = output;

    // Ensure that our destroy listener is always first in the wlr_output destroy
    // listener list. This must be done before creating the scene output since
    // creating the scene output may send enter events, creating wlr_surface_output
    // objects with their own output destroy listeners.
    // This is part of a workaround for an upstream wlroots bug where certain valid
    // destroy orderings result in assertion failure.
    // TODO(wlroots) https://gitlab.freedesktop.org/wlroots/wlroots/-/work_items/4096
    wlr_output.events.destroy.add(&output.destroy);
    errdefer output.destroy.link.remove();

    output.scene_output = try server.scene.wlr_scene.createSceneOutput(wlr_output);
    errdefer comptime unreachable;

    server.om.outputs.append(output);
    output.link_sent.init();

    wlr_output.events.request_state.add(&output.request_state);
    wlr_output.events.frame.add(&output.frame);
    wlr_output.events.present.add(&output.present);
    output.retry_timer = server.wl_server.getEventLoop().addTimer(*Output, handleRetry, output) catch null;

    output.scheduled.state = .enabled;
    if (wlr_output.preferredMode()) |preferred_mode| {
        output.scheduled.mode = .{ .standard = preferred_mode };
    } else {
        // The output does not support modes (i.e. we are not using the DRM backend)
        // Currently, wlroots does not make it possible for us know the dimensions
        // requested by the host compositor in the first configure event. Therefore,
        // we can't do anything but guess until the second configure is sent and
        // wlroots emits the wlr_output request_state event.
        // TODO(wlroots): fix this API limitation, for context see
        // https://gitlab.freedesktop.org/wlroots/wlroots/-/merge_requests/4963
        output.scheduled.mode = .{ .custom = .{ .width = 1280, .height = 720, .refresh = 0 } };
    }

    server.wm.dirtyWindowing();
}

fn handleDestroy(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    const output: *Output = @fieldParentPtr("destroy", listener);

    log.debug("wlr_output '{s}' destroyed", .{wlr_output.name});

    // Ensure that the wlr_scene_output is destroyed before any possible
    // modifications to the scene graph that might result in output enter/leave
    // events being sent can be made.
    //
    // Furthermore, ensure that the output is removed from the wlr_output_layout
    // to ensure that no output enter events for cursor surfaces will be sent by
    // wlroots during destruction.
    //
    // We have guaranteed in Output.create() that our handleDestroy() listener
    // is first in the wlr_output's destroy listener list, so this workaround
    // is always applied before any other destroy listeners are called.
    //
    // This is part of a workaround for an upstream wlroots bug where certain valid
    // destroy orderings result in assertion failure.
    // TODO(wlroots) https://gitlab.freedesktop.org/wlroots/wlroots/-/work_items/4096
    output.scene_output.?.destroy();
    server.om.output_layout.remove(wlr_output);

    {
        var it = server.layer_shell.surfaces.iterator();
        while (it.next()) |surface| {
            if (surface.wlr_layer_surface.output == wlr_output) {
                surface.wlr_layer_surface.destroy();
            }
        }
    }
    {
        var it = server.input_manager.devices.iterator(.forward);
        while (it.next()) |device| {
            if (device.config.map_to_output == wlr_output) {
                device.config.map_to_output = null;
                device.seat.cursor.wlr_cursor.mapInputToOutput(device.wlr_device, null);
            }
        }
    }

    output.destroy.link.remove();
    output.request_state.link.remove();
    output.frame.link.remove();
    output.present.link.remove();
    if (output.retry_timer) |timer| timer.remove();
    output.retry_timer = null;

    wlr_output.data = null;

    output.wlr_output = null;
    output.scene_output = null;
    output.scheduled.mode = .none;
    output.sent.mode = .none;
    output.current.mode = .none;
    output.scheduled.state = .destroying;

    server.wm.dirtyWindowing();
}

pub fn manageStart(output: *Output) void {
    switch (output.scheduled.state) {
        .enabled, .disabled_soft => {
            // We cannot send 0 width/height to the window manager client.
            assert(output.scheduled.mode != .none);

            const wlr_output = output.wlr_output.?;

            output.layer_shell.manageStart();

            if (server.wm.object) |wm_v1| {
                const new = output.object == null;
                const output_v1 = output.object orelse blk: {
                    const output_v1 = river.OutputV1.create(wm_v1.getClient(), wm_v1.getVersion(), 0) catch {
                        log.err("out of memory", .{});
                        return; // try again next update
                    };
                    output.object = output_v1;

                    output_v1.setHandler(*Output, handleRequest, handleObjectDestroy, output);
                    wm_v1.sendOutput(output_v1);

                    break :blk output_v1;
                };
                errdefer comptime unreachable;

                if (!output.sent_wl_output) {
                    // wl_output globals are created/destroyed by the wlroots output layout.
                    if (wlr_output.global) |global| {
                        output_v1.sendWlOutput(global.getName(output_v1.getClient()));
                        output.sent_wl_output = true;
                    }
                }

                const scheduled = &output.scheduled;
                const sent = &output.sent;

                const scheduled_width, const scheduled_height = scheduled.dimensions();
                const sent_width, const sent_height = sent.dimensions();

                if (new or scheduled_width != sent_width or scheduled_height != sent_height) {
                    output_v1.sendDimensions(scheduled_width, scheduled_height);
                }
                if (new or scheduled.x != sent.x or scheduled.y != sent.y) {
                    output_v1.sendPosition(scheduled.x, scheduled.y);
                }

                if (new or scheduled.capture_session_count != sent.capture_session_count) {
                    if (output_v1.getVersion() >= 5) {
                        output_v1.sendCaptureSessions(scheduled.capture_session_count);
                    }
                }
            }

            output.sent = output.scheduled;

            output.link_sent.remove();
            server.wm.sent.outputs.append(output);
        },
        .disabled_hard, .destroying => {
            output.makeInert();

            output.sent = output.scheduled;

            if (output.scheduled.state == .destroying) {
                assert(output.wlr_output == null);
                {
                    var it = server.wm.windows.iterator();
                    while (it.next()) |window| {
                        switch (window.wm_scheduled.fullscreen_requested) {
                            .fullscreen => |output_hint| {
                                if (output_hint == output) {
                                    window.wm_scheduled.fullscreen_requested = .{ .fullscreen = null };
                                }
                            },
                            .no_request, .exit => {},
                        }
                        if (window.wm_requested.fullscreen == output) {
                            window.wm_requested.fullscreen = null;
                        }
                    }
                }
                output.link.remove();
                output.link_sent.remove();

                util.gpa.destroy(output);
            }
        },
    }
}

pub fn makeInert(output: *Output) void {
    if (output.object) |output_v1| {
        output_v1.sendRemoved();
        output_v1.setHandler(?*anyopaque, handleRequestInert, null, null);
        output.layer_shell.makeInert();
        handleObjectDestroy(output_v1, output);
    }
}

fn handleRequestInert(
    output_v1: *river.OutputV1,
    request: river.OutputV1.Request,
    _: ?*anyopaque,
) void {
    if (request == .destroy) output_v1.destroy();
}

fn handleObjectDestroy(_: *river.OutputV1, output: *Output) void {
    output.object = null;
    output.sent_wl_output = false;
}

fn handleRequest(
    output_v1: *river.OutputV1,
    request: river.OutputV1.Request,
    output: *Output,
) void {
    assert(output.object == output_v1);
    switch (request) {
        .destroy => output_v1.destroy(),
        .set_presentation_mode => |args| {
            if (!server.wm.ensureRendering()) return;
            output.rendering_requested.tearing = switch (args.mode) {
                .vsync => false,
                .async => true,
                _ => {
                    output_v1.postError(.invalid_presentation_mode, "invalid presentation mode enum value");
                    return;
                },
            };
        },
    }
}

fn handleRequestState(listener: *wl.Listener(*wlr.Output.event.RequestState), event: *wlr.Output.event.RequestState) void {
    const output: *Output = @fieldParentPtr("request_state", listener);

    // The only state currently requested by a wlroots backend is a
    // custom mode as the Wayland/X11 backend window is resized.
    const committed: u32 = @bitCast(event.state.committed);
    const supported: u32 = @bitCast(wlr.Output.State.Fields{ .mode = true });

    if (committed != supported) {
        log.err("backend requested unsupported state {}", .{committed});
        return;
    }

    log.debug("backend requested new mode", .{});

    if (event.state.mode) |mode| {
        output.scheduled.mode = .{ .standard = mode };
    } else {
        output.scheduled.mode = .{ .custom = .{
            .width = event.state.custom_mode.width,
            .height = event.state.custom_mode.height,
            .refresh = event.state.custom_mode.refresh,
        } };
    }

    server.wm.dirtyWindowing();
}

/// Pangolin: PANGOLIN_PROFILE set logs how long each rendered frame took and
/// when it started (CLOCK_MONOTONIC milliseconds, as the shell's own frame
/// log), to tell the compositor's share of a slow animation from the shell's.
var profile: ?bool = null;
var profile_previous: f64 = 0;

fn msecs(timespec: posix.timespec) f64 {
    return @as(f64, @floatFromInt(timespec.sec)) * 1000 +
        @as(f64, @floatFromInt(timespec.nsec)) / 1_000_000;
}

fn handleFrame(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    const output: *Output = @fieldParentPtr("frame", listener);

    const profiling = profile orelse blk: {
        profile = std.c.getenv("PANGOLIN_PROFILE") != null;
        break :blk profile.?;
    };
    const start = if (profiling) msecs(util.timestamp()) else 0;
    const needs_frame = profiling and output.scene_output.?.needsFrame();

    server.window_effects.beforeFrame();
    server.splash.beforeFrame();
    server.blur.beforeFrame();

    if (output.renderAndCommit()) |_| {
        output.retries = 0;
    } else |err| switch (err) {
        error.CommitFailed => {
            // One retry usually does it; a persistent failure waits for the
            // next change.
            if (output.retries < 10) {
                if (output.retry_timer) |timer| timer.timerUpdate(1) catch {};
            } else if (output.retries == 10) {
                log.err("output commit failed for {s}", .{wlr_output.name});
            }
            output.retries +|= 1;
        },
    }

    var now = util.timestamp();
    if (needs_frame) {
        const end = msecs(now);
        log.info("frame: render {d:.1}ms, since previous {d:.1}ms, at {d:.0}ms", .{
            end - start,
            start - profile_previous,
            start,
        });
        profile_previous = start;
    }
    output.scene_output.?.sendFrameDone(&now);
    server.window_effects.afterFrame(output, &now);
    server.blur.afterFrame(&now);
}

fn handleRetry(output: *Output) c_int {
    if (output.wlr_output) |wlr_output| wlr_output.scheduleFrame();
    return 0;
}

fn renderAndCommit(output: *Output) !void {
    if (!output.scene_output.?.needsFrame()) return;

    const wlr_output = output.wlr_output.?;

    var state = wlr.Output.State.init();
    defer state.finish();

    output.current.applyNoModeset(&state);

    if (!output.scene_output.?.buildState(&state, null)) return error.CommitFailed;

    if (output.rendering_current.tearing) {
        state.tearing_page_flip = true;
        // TODO don't try this every frame if it consistently fails. Stop trying if it fails
        // for 10 frames in a row or something.
        if (!wlr_output.testState(&state)) {
            log.info("tearing page flip test failed for {s}, retrying without tearing", .{wlr_output.name});
            state.tearing_page_flip = false;
        }
    }

    if (!wlr_output.commitState(&state)) return error.CommitFailed;

    switch (server.lock_manager.state) {
        .unlocked => {
            if (output.lock_render_state != .unlocked) {
                output.lock_render_state = .pending_unlock;
            }
        },
        .locked => {
            assert(!server.scene.normal_tree.node.enabled);
            switch (output.lock_render_state) {
                .pending_unlock, .unlocked, .pending_blank, .pending_lock_surface => unreachable,
                .blanked, .lock_surface => {},
            }
        },
        .waiting_for_blank => {
            assert(!server.scene.normal_tree.node.enabled);
            if (output.lock_render_state != .blanked) {
                output.lock_render_state = .pending_blank;
            }
        },
        .waiting_for_lock_surfaces => {
            const lock_surface_mapped = blk: {
                if (server.lock_manager.lockSurfaceFromOutput(output)) |lock_surface| {
                    break :blk lock_surface.wlr_lock_surface.surface.mapped;
                } else {
                    break :blk false;
                }
            };
            if (lock_surface_mapped) {
                if (output.lock_render_state != .lock_surface) {
                    output.lock_render_state = .pending_lock_surface;
                }
            } else {
                if (output.lock_render_state != .unlocked) {
                    output.lock_render_state = .pending_unlock;
                }
            }
        },
    }
}

fn handlePresent(
    listener: *wl.Listener(*wlr.Output.event.Present),
    event: *wlr.Output.event.Present,
) void {
    const output: *Output = @fieldParentPtr("present", listener);
    if (!event.presented) {
        return;
    }
    switch (output.lock_render_state) {
        .pending_unlock => {
            assert(server.lock_manager.state != .locked);
            output.lock_render_state = .unlocked;
        },
        .unlocked => assert(server.lock_manager.state != .locked),
        .pending_blank => {
            output.lock_render_state = .blanked;
            if (server.lock_manager.state != .locked) {
                server.lock_manager.maybeLock();
            }
        },
        .pending_lock_surface => {
            output.lock_render_state = .lock_surface;
            if (server.lock_manager.state != .locked) {
                server.lock_manager.maybeLock();
            }
        },
        .blanked, .lock_surface => {},
    }
}
