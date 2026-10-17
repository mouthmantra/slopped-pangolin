// SPDX-FileCopyrightText: © 2026 The dahliaOS Authors
// SPDX-License-Identifier: GPL-3.0-only

//! Pangolin: shows the user's wallpaper on every output from river's very
//! first frame, below everything, so the session starts on the wallpaper
//! instead of a black screen while the shell starts up.
//!
//! The image is a raw file the shell keeps up to date (PANGOLIN_SPLASH): a
//! 16 byte header ("PSPL", width, height, 0 as little endian u32) followed
//! by width * height ARGB8888 pixels (B, G, R, A bytes). It is shown
//! cropped to cover each output and dropped a while after the shell's
//! desktop surface covers it.

const Splash = @This();

const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const server = &@import("main.zig").server;
const util = @import("util.zig");

const log = std.log.scoped(.output);

const max_file_size = 96 * 1024 * 1024;

tree: ?*wlr.SceneTree = null,
buffer: ?*SplashBuffer = null,
nodes: std.ArrayList(Node) = .empty,
dismiss_timer: ?*wl.EventSource = null,
/// Fade-in from black (PANGOLIN_SPLASH_FADE, in ms): a session started from
/// a black screen (a TTY, another display manager) comes in smoothly
/// instead of cutting to the wallpaper. Pangolin's login screen hands over
/// on the wallpaper itself, so sessions it starts don't fade.
fade_ms: u32 = 0,
fade_start: ?u32 = null,

const Node = struct {
    output: *wlr.Output,
    scene_buffer: *wlr.SceneBuffer,
};

pub fn init(splash: *Splash) void {
    splash.* = .{};
    const path = mem.sliceTo(std.c.getenv("PANGOLIN_SPLASH") orelse return, 0);
    const buffer = SplashBuffer.load(path) catch |err| {
        if (err != error.FileNotFound) log.info("no splash image ({s}): {s}", .{ path, @errorName(err) });
        return;
    };
    const tree = server.scene.wlr_scene.tree.createSceneTree() catch {
        buffer.base.drop();
        return;
    };
    tree.node.lowerToBottom();
    splash.tree = tree;
    splash.buffer = buffer;
    if (std.c.getenv("PANGOLIN_SPLASH_FADE")) |value| {
        splash.fade_ms = std.fmt.parseInt(u32, mem.sliceTo(value, 0), 10) catch 0;
    }
}

pub fn deinit(splash: *Splash) void {
    splash.clear();
}

fn clear(splash: *Splash) void {
    if (splash.dismiss_timer) |timer| timer.remove();
    splash.dismiss_timer = null;
    splash.nodes.deinit(util.gpa);
    splash.nodes = .empty;
    if (splash.tree) |tree| tree.node.destroy();
    splash.tree = null;
    if (splash.buffer) |buffer| buffer.base.drop();
    splash.buffer = null;
}

/// Right before an output renders: every enabled output shows the image.
pub fn beforeFrame(splash: *Splash) void {
    const tree = splash.tree orelse return;
    const buffer = splash.buffer orelse return;
    var it = server.om.outputs.iterator(.forward);
    while (it.next()) |output| {
        const wlr_output = output.wlr_output orelse continue;
        if (!wlr_output.enabled) continue;
        var box: wlr.Box = undefined;
        server.om.output_layout.getBox(wlr_output, &box);
        if (box.width <= 0 or box.height <= 0) continue;

        const node = for (splash.nodes.items) |*node| {
            if (node.output == wlr_output) break node;
        } else blk: {
            const scene_buffer = tree.createSceneBuffer(&buffer.base) catch return;
            splash.nodes.append(util.gpa, .{ .output = wlr_output, .scene_buffer = scene_buffer }) catch {
                scene_buffer.node.destroy();
                return;
            };
            break :blk &splash.nodes.items[splash.nodes.items.len - 1];
        };
        node.scene_buffer.node.setPosition(box.x, box.y);
        node.scene_buffer.setDestSize(box.width, box.height);
        // Cover: crop the image to the output's aspect ratio.
        const iw: f64 = @floatFromInt(buffer.base.width);
        const ih: f64 = @floatFromInt(buffer.base.height);
        const ow: f64 = @floatFromInt(box.width);
        const oh: f64 = @floatFromInt(box.height);
        var src: wlr.FBox = .{ .x = 0, .y = 0, .width = iw, .height = ih };
        if (iw / ih > ow / oh) {
            src.width = ih * ow / oh;
            src.x = (iw - src.width) / 2;
        } else {
            src.height = iw * oh / ow;
            src.y = (ih - src.height) / 2;
        }
        node.scene_buffer.setSourceBox(&src);
    }
    if (splash.fade_ms > 0) splash.fade();
}

fn fade(splash: *Splash) void {
    const now = util.msecTimestamp();
    const start = splash.fade_start orelse blk: {
        splash.fade_start = now;
        break :blk now;
    };
    const t = @min(1.0, @as(f32, @floatFromInt(now -% start)) / @as(f32, @floatFromInt(splash.fade_ms)));
    // Ease out (cubic).
    const opacity = 1 - (1 - t) * (1 - t) * (1 - t);
    for (splash.nodes.items) |node| {
        node.scene_buffer.setOpacity(opacity);
        if (t < 1) node.output.scheduleFrame();
    }
    if (t >= 1) splash.fade_ms = 0;
}

/// The shell's desktop surface is up: it covers the image from now on,
/// which is dropped a little later to free its memory.
pub fn desktopMapped(splash: *Splash) void {
    if (splash.tree == null or splash.dismiss_timer != null) return;
    const timer = server.wl_server.getEventLoop().addTimer(*Splash, handleTimeout, splash) catch return;
    timer.timerUpdate(10_000) catch {};
    splash.dismiss_timer = timer;
}

fn handleTimeout(splash: *Splash) c_int {
    splash.clear();
    return 0;
}

const SplashBuffer = struct {
    base: wlr.Buffer,
    pixels: []u8,
    stride: usize,

    const impl: wlr.Buffer.Impl = .{
        .destroy = destroy,
        .get_dmabuf = null,
        .get_shm = null,
        .begin_data_ptr_access = beginDataPtrAccess,
        .end_data_ptr_access = endDataPtrAccess,
    };

    fn load(path: []const u8) !*SplashBuffer {
        const io = Io.Threaded.global_single_threaded.io();
        const file = try Io.Dir.cwd().openFile(io, path, .{});
        defer file.close(io);
        const size = try file.length(io);
        if (size > max_file_size) return error.InvalidSplash;
        const data = try util.gpa.alloc(u8, @intCast(size));
        errdefer util.gpa.free(data);
        if (try file.readPositionalAll(io, data, 0) != data.len) return error.InvalidSplash;
        if (data.len < 16 or !mem.eql(u8, data[0..4], "PSPL")) return error.InvalidSplash;
        const width = mem.readInt(u32, data[4..8], .little);
        const height = mem.readInt(u32, data[8..12], .little);
        if (width == 0 or height == 0 or width > 16384 or height > 16384) return error.InvalidSplash;
        const stride = @as(usize, width) * 4;
        if (data.len < 16 + stride * height) return error.InvalidSplash;

        const buffer = try util.gpa.create(SplashBuffer);
        buffer.* = .{ .base = undefined, .pixels = data, .stride = stride };
        buffer.base.init(&impl, @intCast(width), @intCast(height));
        return buffer;
    }

    fn destroy(wlr_buffer: *wlr.Buffer) callconv(.c) void {
        const buffer: *SplashBuffer = @fieldParentPtr("base", wlr_buffer);
        util.gpa.free(buffer.pixels);
        util.gpa.destroy(buffer);
    }

    fn beginDataPtrAccess(
        wlr_buffer: *wlr.Buffer,
        flags: u32,
        data: **anyopaque,
        format: *u32,
        stride: *usize,
    ) callconv(.c) bool {
        const buffer: *SplashBuffer = @fieldParentPtr("base", wlr_buffer);
        if (flags & wlr.Buffer.data_ptr_access_flag.write != 0) return false;
        data.* = @ptrCast(buffer.pixels[16..].ptr);
        format.* = 0x34325241; // DRM_FORMAT_ARGB8888
        stride.* = buffer.stride;
        return true;
    }

    fn endDataPtrAccess(_: *wlr.Buffer) callconv(.c) void {}
};
