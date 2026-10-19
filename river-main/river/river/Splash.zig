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
//!
//! With PANGOLIN_WALLPAPER=1 it is the wallpaper for good: it stays, follows
//! the file (replaced by the shell when the wallpaper changes, gone when the
//! shell draws the wallpaper itself), and is drawn opaque. Kept at the
//! output's resolution by the shell, it costs far less to composite than a
//! client surface (GTK draws at an integer scale: 5120x2880 for a 4K output
//! at 1.5).

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
/// PANGOLIN_WALLPAPER: the image stays and follows its file.
keep: bool = false,
path: ?[:0]const u8 = null,
inotify: ?*wl.EventSource = null,
inotify_fd: i32 = -1,

const Node = struct {
    output: *wlr.Output,
    scene_buffer: *wlr.SceneBuffer,
};

pub fn init(splash: *Splash) void {
    splash.* = .{};
    const path = mem.sliceTo(std.c.getenv("PANGOLIN_SPLASH") orelse return, 0);
    const wallpaper = if (std.c.getenv("PANGOLIN_WALLPAPER")) |value|
        mem.eql(u8, mem.sliceTo(value, 0), "1")
    else
        false;
    const buffer = SplashBuffer.load(path) catch |err| blk: {
        if (err != error.FileNotFound) log.info("no splash image ({s}): {s}", .{ path, @errorName(err) });
        // As the wallpaper, it shows once the shell writes it (new users).
        if (!wallpaper) return;
        break :blk null;
    };
    const tree = server.scene.wlr_scene.tree.createSceneTree() catch {
        if (buffer) |b| b.base.drop();
        return;
    };
    tree.node.lowerToBottom();
    splash.tree = tree;
    splash.buffer = buffer;
    if (std.c.getenv("PANGOLIN_SPLASH_FADE")) |value| {
        splash.fade_ms = std.fmt.parseInt(u32, mem.sliceTo(value, 0), 10) catch 0;
    }
    if (wallpaper) splash.watch(path);
}

// inotify (linux/inotify.h).
const in_close_write = 0x8;
const in_moved_from = 0x40;
const in_moved_to = 0x80;
const in_delete = 0x200;
const in_nonblock = 0x800;
const in_cloexec = 0x80000;

/// The wallpaper for good: watch the directory for the file being replaced
/// (written to a temporary file, then renamed) or removed.
fn watch(splash: *Splash, path: []const u8) void {
    splash.keep = true;
    const owned = util.gpa.dupeZ(u8, path) catch return;
    splash.path = owned;
    const dir = std.fs.path.dirname(path) orelse ".";
    const dir_z = util.gpa.dupeZ(u8, dir) catch return;
    defer util.gpa.free(dir_z);
    const fd_rc = std.os.linux.inotify_init1(in_nonblock | in_cloexec);
    if (std.os.linux.errno(fd_rc) != .SUCCESS) return;
    const fd: i32 = @intCast(fd_rc);
    const wd = std.os.linux.inotify_add_watch(fd, dir_z, in_close_write | in_moved_to | in_moved_from | in_delete);
    if (std.os.linux.errno(wd) != .SUCCESS) {
        _ = std.os.linux.close(fd);
        return;
    }
    splash.inotify_fd = fd;
    splash.inotify = server.wl_server.getEventLoop().addFd(*Splash, fd, .{ .readable = true }, handleInotify, splash) catch null;
}

fn handleInotify(fd: c_int, _: wl.EventMask, splash: *Splash) c_int {
    const path = splash.path orelse return 0;
    const name = std.fs.path.basename(path);
    var buf: [4096]u8 align(@alignOf(u32)) = undefined;
    var changed = false;
    while (true) {
        const rc = std.os.linux.read(fd, &buf, buf.len);
        if (std.os.linux.errno(rc) != .SUCCESS or rc == 0) break;
        var i: usize = 0;
        while (i + 16 <= rc) {
            const len = mem.readInt(u32, buf[i + 12 ..][0..4], .native);
            const event_name = mem.sliceTo(buf[i + 16 .. i + 16 + len], 0);
            if (mem.eql(u8, event_name, name)) changed = true;
            i += 16 + len;
        }
    }
    if (changed) splash.reload();
    return 0;
}

/// The file changed: show the new image, or nothing if it's gone.
fn reload(splash: *Splash) void {
    const path = splash.path orelse return;
    const buffer = SplashBuffer.load(path) catch null;
    for (splash.nodes.items) |node| node.scene_buffer.node.destroy();
    splash.nodes.clearRetainingCapacity();
    if (splash.buffer) |old| old.base.drop();
    splash.buffer = buffer;
    var it = server.om.outputs.iterator(.forward);
    while (it.next()) |output| {
        if (output.wlr_output) |wlr_output| wlr_output.scheduleFrame();
    }
    log.info("wallpaper {s}", .{if (buffer != null) "updated" else "removed"});
}

pub fn deinit(splash: *Splash) void {
    splash.clear();
}

fn clear(splash: *Splash) void {
    if (splash.inotify) |source| source.remove();
    splash.inotify = null;
    if (splash.inotify_fd >= 0) _ = std.os.linux.close(splash.inotify_fd);
    splash.inotify_fd = -1;
    if (splash.path) |path| util.gpa.free(path);
    splash.path = null;
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
    var it = server.om.outputs.iterator(.forward);
    while (it.next()) |output| {
        const wlr_output = output.wlr_output orelse continue;
        if (!wlr_output.enabled) continue;
        var box: wlr.Box = undefined;
        server.om.output_layout.getBox(wlr_output, &box);
        splash.place(wlr_output, box);
    }
    if (splash.fade_ms > 0) splash.fade();
}

/// Right before an output is turned on (at box): the frame that turns it on
/// shows the image too, instead of a black one (after the login screen's
/// wallpaper, a black flash).
pub fn beforeModeset(splash: *Splash, wlr_output: *wlr.Output, box: wlr.Box) void {
    splash.place(wlr_output, box);
    if (splash.fade_ms > 0) splash.fade();
}

fn place(splash: *Splash, wlr_output: *wlr.Output, box: wlr.Box) void {
    const tree = splash.tree orelse return;
    const buffer = splash.buffer orelse return;
    if (box.width <= 0 or box.height <= 0) return;

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
    if (splash.keep) return;
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
        // The shell writes opaque pixels: XRGB, so that it's drawn without
        // blending.
        format.* = 0x34325258; // DRM_FORMAT_XRGB8888
        stride.* = buffer.stride;
        return true;
    }

    fn endDataPtrAccess(_: *wlr.Buffer) callconv(.c) void {}
};
