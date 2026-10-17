// SPDX-FileCopyrightText: © 2026 The dahliaOS Authors
// SPDX-License-Identifier: GPL-3.0-only

//! river_blur_v1: frosted glass behind parts of surfaces (downstream extension
//! for the Pangolin desktop).
//!
//! Right before an output frame, the scene graph is walked in rendering order.
//! When a surface with blur regions is reached, everything drawn before it
//! (i.e. below it) inside each region is rendered into a small offscreen
//! buffer, blurred by successive bilinear downsampling and upsampling, clipped
//! to the region's rounded rectangle and shown by a scene buffer placed right
//! below the surface. A blur is only redrawn when what is below it changed.
//!
//! Version 2 adds animations of parts of a surface (popups opening and
//! closing), run by river at the refresh rate of the outputs: the part is
//! drawn by a scene buffer of its own, transformed every frame, along with the
//! blurs inside it.

const Blur = @This();

const std = @import("std");
const math = std.math;
const pixman = @import("pixman");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;
const river = @import("wayland").server.river;

const server = &@import("main.zig").server;
const util = @import("util.zig");

const SceneNodeData = @import("SceneNodeData.zig");

const log = std.log.scoped(.wm);

/// Bilinear halvings after the half resolution base: the blur radius roughly
/// doubles with each level.
const max_levels = 6;

/// How far around a blur region the blur reads, in logical pixels: a strong
/// blur needs what is around the region, and a thin one (a title bar) would
/// otherwise run out of halvings after a few levels.
const reach = 96;

/// Grain over the blur, frosted glass like dahliaOS's acrylic: a tile of
/// random grays drawn under the client's tint (80% opaque), so about 2% of
/// it shows, as in dahliaOS.
const noise_size = 128;
const noise_alpha = 26;

global: *wl.Global,
/// See [noise_size]; made with the renderer, dropped with it.
noise: ?*wlr.Texture = null,
surfaces: wl.list.Head(BlurSurface, .link),
/// Scene buffers showing blurs, so that a blur below another one is drawn
/// from its blurred content.
nodes: std.AutoHashMapUnmanaged(*wlr.SceneBuffer, *Node) = .empty,
/// Scratch lists reused every frame.
items: std.ArrayList(Item) = .empty,
updates: std.ArrayList(Update) = .empty,

server_destroy: wl.Listener(*wl.Server) = .init(handleServerDestroy),

pub fn init(blur: *Blur) !void {
    blur.* = .{
        .global = try wl.Global.create(server.wl_server, river.BlurManagerV1, 3, ?*anyopaque, null, bind),
        .surfaces = undefined,
    };
    blur.surfaces.init();
    server.wl_server.addDestroyListener(&blur.server_destroy);
}

fn handleServerDestroy(listener: *wl.Listener(*wl.Server), _: *wl.Server) void {
    const blur: *Blur = @fieldParentPtr("server_destroy", listener);
    blur.global.destroy();
    blur.items.deinit(util.gpa);
    blur.updates.deinit(util.gpa);
    blur.nodes.deinit(util.gpa);
}

fn bind(client: *wl.Client, _: ?*anyopaque, version: u32, id: u32) void {
    const manager = river.BlurManagerV1.create(client, version, id) catch {
        client.postNoMemory();
        log.err("out of memory", .{});
        return;
    };
    manager.setHandler(?*anyopaque, handleManagerRequest, null, null);
}

fn handleManagerRequest(
    manager: *river.BlurManagerV1,
    request: river.BlurManagerV1.Request,
    _: ?*anyopaque,
) void {
    switch (request) {
        .destroy => manager.destroy(),
        .get_blur => |args| {
            const surface = wlr.Surface.fromWlSurface(args.surface);
            if (server.blur.find(surface) != null) {
                manager.postError(.blur_exists, "the surface already has a river_blur_v1");
                return;
            }
            const resource = river.BlurV1.create(manager.getClient(), manager.getVersion(), args.id) catch {
                manager.postNoMemory();
                log.err("out of memory", .{});
                return;
            };
            BlurSurface.create(resource, surface) catch {
                resource.postNoMemory();
                log.err("out of memory", .{});
            };
        },
    }
}

fn find(blur: *Blur, surface: *wlr.Surface) ?*BlurSurface {
    var it = blur.surfaces.iterator(.forward);
    while (it.next()) |blur_surface| {
        if (blur_surface.surface == surface) return blur_surface;
    }
    return null;
}

/// Drops every offscreen buffer, before the renderer they belong to goes
/// away (GPU reset).
pub fn dropBuffers(blur: *Blur) void {
    if (blur.noise) |texture| texture.destroy();
    blur.noise = null;
    var it = blur.surfaces.iterator(.forward);
    while (it.next()) |blur_surface| {
        for (blur_surface.effects.items) |effect| effect.destroy();
        blur_surface.effects.clearRetainingCapacity();
        for (blur_surface.nodes.items) |node| node.reset();
        // Corner cutouts render with the renderer too.
        for (blur_surface.cutout_nodes.items) |node| node.reset();
    }
}

fn noiseTexture(blur: *Blur) ?*wlr.Texture {
    if (blur.noise) |texture| return texture;
    // Premultiplied ARGB8888: gray of random brightness, constant opacity.
    var pixels: [noise_size * noise_size]u32 = undefined;
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const random = prng.random();
    for (&pixels) |*pixel| {
        const c: u32 = @as(u32, random.int(u8)) * noise_alpha / 255;
        pixel.* = (@as(u32, noise_alpha) << 24) | (c << 16) | (c << 8) | c;
    }
    blur.noise = wlr.Texture.fromPixels(server.renderer, 0x34325241, noise_size * 4, noise_size, noise_size, &pixels);
    return blur.noise;
}

/// What the blur of [box] reads: [reach] around it, within the outputs (and
/// never less than the region itself).
fn readArea(box: wlr.Box) wlr.Box {
    var layout: wlr.Box = undefined;
    server.om.output_layout.getBox(null, &layout);
    const x0 = @min(box.x, @max(box.x - reach, layout.x));
    const y0 = @min(box.y, @max(box.y - reach, layout.y));
    const x1 = @max(box.x + box.width, @min(box.x + box.width + reach, layout.x + layout.width));
    const y1 = @max(box.y + box.height, @min(box.y + box.height + reach, layout.y + layout.height));
    return .{ .x = x0, .y = y0, .width = x1 - x0, .height = y1 - y0 };
}

const Region = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    /// Top left, top right, bottom right, bottom left.
    radii: [4]i32,
    alpha: f32,
    /// Pangolin: a corner cutout (set_cutouts) rather than a blur: which
    /// corner of the window (0 top left ... 3 bottom left).
    cutout: ?u2 = null,
};

/// Something drawn below a blur, in layout coordinates.
const Item = struct {
    box: wlr.Box,
    kind: union(enum) {
        buffer: *wlr.SceneBuffer,
        rect: *wlr.SceneRect,
        blur: *Node,
    },
    /// Changes whenever the content changes.
    key: u64,
};

/// A surface with blur regions reached while walking the scene: its blurs are
/// drawn from the first `below` items once the walk is over.
const Update = struct {
    blur_surface: *BlurSurface,
    scene_buffer: *wlr.SceneBuffer,
    x: i32,
    y: i32,
    below: usize,
};

/// Right before an output renders: bring every visible blur up to date.
pub fn beforeFrame(blur: *Blur) void {
    if (blur.surfaces.empty()) return;
    // Blurs are drawn with GLES2, animations work with any renderer.
    const gles2 = server.renderer.isGles2();

    blur.items.clearRetainingCapacity();
    blur.updates.clearRetainingCapacity();
    blur.collect(&server.scene.wlr_scene.tree, 0, 0) catch {
        log.err("out of memory", .{});
        return;
    };

    const scale = maxOutputScale();
    const now = nanoTimestamp();
    for (blur.updates.items) |update| {
        // Cutouts show the surface itself too (the shadow under the corner).
        const with_self = blur.items.items[0..@min(update.below + 1, blur.items.items.len)];
        update.blur_surface.update(update, blur.items.items[0..update.below], with_self, scale, now, gles2);
    }

    // Animations of surfaces that weren't drawn (hidden) end anyway.
    var animating = false;
    var it = blur.surfaces.iterator(.forward);
    while (it.next()) |blur_surface| {
        var i: usize = 0;
        while (i < blur_surface.effects.items.len) {
            const effect = blur_surface.effects.items[i];
            if (now - effect.requested > effect.duration + 500 * std.time.ns_per_ms) {
                _ = blur_surface.effects.orderedRemove(i);
                effect.destroy();
                continue;
            }
            animating = true;
            i += 1;
        }
    }
    if (animating) scheduleFrames();
}

/// After an output frame: surfaces hidden behind their animated parts still
/// get frame callbacks.
pub fn afterFrame(blur: *Blur, now: *const std.posix.timespec) void {
    var it = blur.surfaces.iterator(.forward);
    while (it.next()) |blur_surface| {
        for (blur_surface.effects.items) |effect| {
            if (effect.kind == .reveal) {
                blur_surface.surface.sendFrameDone(now);
                break;
            }
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

fn collect(blur: *Blur, tree: *wlr.SceneTree, x: i32, y: i32) !void {
    var it = tree.children.iterator(.forward);
    while (it.next()) |node| {
        if (!node.enabled) continue;
        const nx = x + node.x;
        const ny = y + node.y;
        switch (node.type) {
            .tree => try blur.collect(wlr.SceneTree.fromNode(node), nx, ny),
            .rect => {
                const rect = wlr.SceneRect.fromNode(node);
                if (rect.width <= 0 or rect.height <= 0) continue;
                try blur.items.append(util.gpa, .{
                    .box = .{ .x = nx, .y = ny, .width = rect.width, .height = rect.height },
                    .kind = .{ .rect = rect },
                    .key = std.hash.Wyhash.hash(0, std.mem.asBytes(&rect.color)),
                });
            },
            .buffer => {
                const scene_buffer = wlr.SceneBuffer.fromNode(node);
                if (blur.nodes.get(scene_buffer)) |blur_node| {
                    try blur.items.append(util.gpa, .{
                        .box = .{ .x = nx, .y = ny, .width = blur_node.logical_width, .height = blur_node.logical_height },
                        .kind = .{ .blur = blur_node },
                        .key = blur_node.generation,
                    });
                    continue;
                }
                const buffer = scene_buffer.buffer orelse continue;
                var seq: u32 = 0;
                if (wlr.SceneSurface.tryFromBuffer(scene_buffer)) |scene_surface| {
                    seq = scene_surface.surface.current.seq;
                    if (blur.find(scene_surface.surface)) |blur_surface| {
                        try blur.updates.append(util.gpa, .{
                            .blur_surface = blur_surface,
                            .scene_buffer = scene_buffer,
                            .x = nx,
                            .y = ny,
                            .below = blur.items.items.len,
                        });
                    }
                }
                const width = if (scene_buffer.dst_width > 0) scene_buffer.dst_width else buffer.width;
                const height = if (scene_buffer.dst_height > 0) scene_buffer.dst_height else buffer.height;
                if (width <= 0 or height <= 0) continue;
                try blur.items.append(util.gpa, .{
                    .box = .{ .x = nx, .y = ny, .width = width, .height = height },
                    .kind = .{ .buffer = scene_buffer },
                    .key = @intFromPtr(buffer) ^ (@as(u64, seq) << 48) ^
                        @as(u64, @intFromFloat(scene_buffer.opacity * 255)),
                });
            },
        }
    }
}

fn maxOutputScale() f32 {
    var scale: f32 = 1;
    var it = server.om.outputs.iterator(.forward);
    while (it.next()) |output| {
        if (output.wlr_output) |wlr_output| {
            if (wlr_output.enabled) scale = @max(scale, wlr_output.scale);
        }
    }
    return scale;
}

const BlurSurface = struct {
    resource: *river.BlurV1,
    surface: *wlr.Surface,
    link: wl.list.Link,

    pending: std.ArrayList(Region) = .empty,
    has_pending: bool = false,
    current: std.ArrayList(Region) = .empty,
    nodes: std.ArrayList(*Node) = .empty,
    /// Corner cutouts (set_cutouts), one region per rounded corner.
    pending_cutouts: std.ArrayList(Region) = .empty,
    has_pending_cutouts: bool = false,
    cutouts: std.ArrayList(Region) = .empty,
    cutout_nodes: std.ArrayList(*Node) = .empty,
    /// Parts of the surface being animated.
    effects: std.ArrayList(*Effect) = .empty,

    commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
    surface_destroy: wl.Listener(*wlr.Surface) = .init(handleSurfaceDestroy),

    fn create(resource: *river.BlurV1, surface: *wlr.Surface) !void {
        const blur_surface = try util.gpa.create(BlurSurface);
        blur_surface.* = .{ .resource = resource, .surface = surface, .link = undefined };
        server.blur.surfaces.append(blur_surface);
        surface.events.commit.add(&blur_surface.commit);
        surface.events.destroy.add(&blur_surface.surface_destroy);
        resource.setHandler(*BlurSurface, handleRequest, handleResourceDestroy, blur_surface);
    }

    fn destroy(blur_surface: *BlurSurface) void {
        for (blur_surface.effects.items) |effect| effect.destroy();
        blur_surface.effects.deinit(util.gpa);
        for (blur_surface.nodes.items) |node| node.destroy();
        blur_surface.nodes.deinit(util.gpa);
        blur_surface.pending.deinit(util.gpa);
        blur_surface.current.deinit(util.gpa);
        for (blur_surface.cutout_nodes.items) |node| node.destroy();
        blur_surface.cutout_nodes.deinit(util.gpa);
        blur_surface.pending_cutouts.deinit(util.gpa);
        blur_surface.cutouts.deinit(util.gpa);
        blur_surface.commit.link.remove();
        blur_surface.surface_destroy.link.remove();
        blur_surface.link.remove();
        util.gpa.destroy(blur_surface);
    }

    fn handleRequest(
        resource: *river.BlurV1,
        request: river.BlurV1.Request,
        blur_surface: *BlurSurface,
    ) void {
        switch (request) {
            .destroy => resource.destroy(),
            .set_regions => |args| {
                const values = args.regions.slice(i32);
                blur_surface.pending.clearRetainingCapacity();
                var i: usize = 0;
                while (i + 9 <= values.len) : (i += 9) {
                    const v = values[i .. i + 9];
                    if (v[2] <= 0 or v[3] <= 0) continue;
                    const max_radius = @divTrunc(@min(v[2], v[3]), 2);
                    blur_surface.pending.append(util.gpa, .{
                        .x = v[0],
                        .y = v[1],
                        .width = v[2],
                        .height = v[3],
                        .radii = .{
                            math.clamp(v[4], 0, max_radius),
                            math.clamp(v[5], 0, max_radius),
                            math.clamp(v[6], 0, max_radius),
                            math.clamp(v[7], 0, max_radius),
                        },
                        .alpha = @as(f32, @floatFromInt(math.clamp(v[8], 0, 10000))) / 10000,
                    }) catch {
                        resource.postNoMemory();
                        return;
                    };
                }
                blur_surface.has_pending = true;
            },
            .set_cutouts => |args| {
                const values = args.cutouts.slice(i32);
                blur_surface.pending_cutouts.clearRetainingCapacity();
                var i: usize = 0;
                while (i + 6 <= values.len) : (i += 6) {
                    const v = values[i .. i + 6];
                    if (v[2] <= 0 or v[3] <= 0) continue;
                    const radius = math.clamp(v[4], 0, @divTrunc(@min(v[2], v[3]), 2));
                    if (radius <= 0) continue;
                    // One small region per rounded corner.
                    for (0..4) |corner| {
                        if (v[5] & (@as(i32, 1) << @intCast(corner)) == 0) continue;
                        var radii: [4]i32 = @splat(0);
                        radii[corner] = radius;
                        blur_surface.pending_cutouts.append(util.gpa, .{
                            .x = if (corner == 0 or corner == 3) v[0] else v[0] + v[2] - radius,
                            .y = if (corner == 0 or corner == 1) v[1] else v[1] + v[3] - radius,
                            .width = radius,
                            .height = radius,
                            .radii = radii,
                            .alpha = 1,
                            .cutout = @intCast(corner),
                        }) catch {
                            resource.postNoMemory();
                            return;
                        };
                    }
                }
                blur_surface.has_pending_cutouts = true;
            },
            .reveal => |args| blur_surface.animate(.reveal, .{
                .x = args.x,
                .y = args.y,
                .width = args.width,
                .height = args.height,
            }, .{
                .dx = @floatFromInt(args.dx),
                .dy = @floatFromInt(args.dy),
                .scale = @as(f64, @floatFromInt(math.clamp(args.scale, 0, 40000))) / 10000,
                .opacity = @as(f64, @floatFromInt(math.clamp(args.opacity, 0, 10000))) / 10000,
            }, args.duration, .{ args.x1, args.y1, args.x2, args.y2 }),
            .conceal => |args| blur_surface.animate(.conceal, .{
                .x = args.x,
                .y = args.y,
                .width = args.width,
                .height = args.height,
            }, .{
                .dx = @floatFromInt(args.dx),
                .dy = @floatFromInt(args.dy),
                .scale = @as(f64, @floatFromInt(math.clamp(args.scale, 0, 40000))) / 10000,
                .opacity = @as(f64, @floatFromInt(math.clamp(args.opacity, 0, 10000))) / 10000,
            }, args.duration, .{ args.x1, args.y1, args.x2, args.y2 }),
        }
    }

    fn animate(
        blur_surface: *BlurSurface,
        kind: Effect.Kind,
        requested_part: wlr.Box,
        state: Transform,
        duration_ms: u32,
        curve: [4]i32,
    ) void {
        const surface = blur_surface.surface;
        const bounds: wlr.Box = .{ .x = 0, .y = 0, .width = surface.current.width, .height = surface.current.height };
        var part: wlr.Box = undefined;
        if (!part.intersection(&requested_part, &bounds)) return;

        // A new animation replaces those of the same part.
        var i: usize = 0;
        while (i < blur_surface.effects.items.len) {
            const other = blur_surface.effects.items[i];
            if (intersects(other.part, part)) {
                _ = blur_surface.effects.orderedRemove(i);
                other.destroy();
            } else i += 1;
        }
        if (duration_ms == 0) return;

        log.debug("{s} part {d},{d} {d}x{d} over {d} ms", .{ @tagName(kind), part.x, part.y, part.width, part.height, duration_ms });
        const effect = Effect.create(blur_surface, kind, part, state, duration_ms, curve) catch {
            log.err("out of memory", .{});
            return;
        };
        blur_surface.effects.append(util.gpa, effect) catch {
            effect.destroy();
            log.err("out of memory", .{});
            return;
        };
        scheduleFrames();
    }

    fn handleResourceDestroy(_: *river.BlurV1, blur_surface: *BlurSurface) void {
        blur_surface.destroy();
    }

    fn handleSurfaceDestroy(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const blur_surface: *BlurSurface = @fieldParentPtr("surface_destroy", listener);
        blur_surface.resource.setHandler(?*anyopaque, handleRequestInert, null, null);
        blur_surface.destroy();
    }

    fn handleRequestInert(resource: *river.BlurV1, request: river.BlurV1.Request, _: ?*anyopaque) void {
        if (request == .destroy) resource.destroy();
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const blur_surface: *BlurSurface = @fieldParentPtr("commit", listener);
        for (blur_surface.effects.items) |effect| effect.committed();
        if (blur_surface.has_pending_cutouts) blur_surface.commitCutouts();
        if (!blur_surface.has_pending) return;
        blur_surface.has_pending = false;

        blur_surface.current.clearRetainingCapacity();
        blur_surface.current.appendSlice(util.gpa, blur_surface.pending.items) catch {
            log.err("out of memory", .{});
            return;
        };
        while (blur_surface.nodes.items.len > blur_surface.current.items.len) {
            blur_surface.nodes.pop().?.destroy();
        }
        while (blur_surface.nodes.items.len < blur_surface.current.items.len) {
            const node = util.gpa.create(Node) catch {
                log.err("out of memory", .{});
                return;
            };
            node.* = .{ .owner = blur_surface };
            blur_surface.nodes.append(util.gpa, node) catch {
                util.gpa.destroy(node);
                log.err("out of memory", .{});
                return;
            };
        }
        for (blur_surface.nodes.items) |node| node.signature = 0;
    }

    fn commitCutouts(blur_surface: *BlurSurface) void {
        blur_surface.has_pending_cutouts = false;
        blur_surface.cutouts.clearRetainingCapacity();
        blur_surface.cutouts.appendSlice(util.gpa, blur_surface.pending_cutouts.items) catch {
            log.err("out of memory", .{});
            return;
        };
        while (blur_surface.cutout_nodes.items.len > blur_surface.cutouts.items.len) {
            blur_surface.cutout_nodes.pop().?.destroy();
        }
        while (blur_surface.cutout_nodes.items.len < blur_surface.cutouts.items.len) {
            const node = util.gpa.create(Node) catch {
                log.err("out of memory", .{});
                return;
            };
            node.* = .{ .owner = blur_surface };
            blur_surface.cutout_nodes.append(util.gpa, node) catch {
                util.gpa.destroy(node);
                log.err("out of memory", .{});
                return;
            };
        }
        for (blur_surface.cutout_nodes.items) |node| node.signature = 0;
    }

    fn update(blur_surface: *BlurSurface, update_: Update, below: []const Item, with_self: []const Item, scale: f32, now: i128, gles2: bool) void {
        // Animations first: they move blurs.
        var i: usize = 0;
        while (i < blur_surface.effects.items.len) {
            const effect = blur_surface.effects.items[i];
            if (effect.step(update_.scene_buffer, now)) {
                i += 1;
            } else {
                _ = blur_surface.effects.orderedRemove(i);
                effect.destroy();
            }
        }
        // One animation ending must not show what another one hides.
        for (blur_surface.effects.items) |effect| {
            if (effect.hiding and effect.surface_node == update_.scene_buffer) {
                if (update_.scene_buffer.opacity != 0) update_.scene_buffer.setOpacity(0);
                break;
            }
        }

        if (!gles2) return;
        const count = @min(blur_surface.current.items.len, blur_surface.nodes.items.len);
        for (blur_surface.current.items[0..count], blur_surface.nodes.items[0..count]) |region, node| {
            var shown = region;
            for (blur_surface.effects.items) |effect| {
                if (effect.kind == .reveal and effect.holds(region)) {
                    shown = effect.transformRegion(region);
                    break;
                }
            }
            node.update(shown, update_, below, scale);
        }
        for (blur_surface.effects.items) |effect| {
            for (effect.ghosts.items, effect.ghost_nodes.items) |region, node| {
                node.update(effect.transformRegion(region), update_, below, scale);
            }
        }
        const cutouts = @min(blur_surface.cutouts.items.len, blur_surface.cutout_nodes.items.len);
        for (blur_surface.cutouts.items[0..cutouts], blur_surface.cutout_nodes.items[0..cutouts]) |region, node| {
            node.update(region, update_, with_self, scale);
        }
    }
};

/// Where an animated part of a surface is drawn: scaled around its center,
/// moved, faded.
const Transform = struct {
    dx: f64 = 0,
    dy: f64 = 0,
    scale: f64 = 1,
    opacity: f64 = 1,

    fn lerp(a: Transform, b: Transform, t: f64) Transform {
        return .{
            .dx = a.dx + (b.dx - a.dx) * t,
            .dy = a.dy + (b.dy - a.dy) * t,
            .scale = a.scale + (b.scale - a.scale) * t,
            .opacity = a.opacity + (b.opacity - a.opacity) * t,
        };
    }
};

/// A scene buffer made by an effect, forgotten if the scene destroys it first
/// (along with the tree of the surface).
const OwnedBuffer = struct {
    scene_buffer: ?*wlr.SceneBuffer = null,
    destroy_listener: wl.Listener(void) = .init(handleDestroy),

    fn get(owned: *OwnedBuffer, parent: *wlr.SceneTree) ?*wlr.SceneBuffer {
        if (owned.scene_buffer) |scene_buffer| return scene_buffer;
        const scene_buffer = parent.createSceneBuffer(null) catch {
            log.err("out of memory", .{});
            return null;
        };
        scene_buffer.point_accepts_input = rejectInput;
        scene_buffer.node.events.destroy.add(&owned.destroy_listener);
        owned.scene_buffer = scene_buffer;
        return scene_buffer;
    }

    fn handleDestroy(listener: *wl.Listener(void)) void {
        const owned: *OwnedBuffer = @fieldParentPtr("destroy_listener", listener);
        owned.destroy_listener.link.remove();
        owned.scene_buffer = null;
    }

    fn destroy(owned: *OwnedBuffer) void {
        const scene_buffer = owned.scene_buffer orelse return;
        owned.destroy_listener.link.remove();
        owned.scene_buffer = null;
        scene_buffer.node.destroy();
    }
};

/// A part of a surface animated in (reveal) or out (conceal).
///
/// Reveal: the surface's own scene buffer is made transparent (it still
/// takes input and gets frame callbacks) and is drawn instead by patches
/// around the part and a transformed copy of the part, all following what the
/// surface commits. Conceal: a copy of the part from the buffer shown when
/// the animation was asked for is drawn above the surface, with copies of the
/// blurs that were inside it; the part itself is hidden the same way until
/// the surface commits (normally the frame without it).
const Effect = struct {
    const Kind = enum { reveal, conceal };

    owner: *BlurSurface,
    kind: Kind,
    /// Surface-local.
    part: wlr.Box,
    from: Transform,
    to: Transform,
    current: Transform,
    requested: i128,
    /// When the animation started (its first frame), 0 before.
    start: i128 = 0,
    duration: i128,
    curve: [4]f64,
    /// A reveal waits for the commit drawing the part (or a short while).
    waiting_commit: bool,
    /// The part is hidden in the surface (drawn by the copy, the rest by
    /// patches).
    hiding: bool = true,

    /// The scene buffer of the surface the effect was set up for.
    surface_node: ?*wlr.SceneBuffer = null,
    surface_node_destroy: wl.Listener(void) = .init(handleSurfaceNodeDestroy),
    surface_opacity: f32 = 1,

    copy: OwnedBuffer = .{},
    patches: [4]OwnedBuffer = @splat(.{}),

    /// Conceal: a copy of the part as shown when the animation was asked for
    /// (the client may draw into its own buffer again right away).
    snapshot: Target = .{},
    /// Conceal: blurs inside the part when the animation was asked for.
    ghosts: std.ArrayList(Region) = .empty,
    ghost_nodes: std.ArrayList(*Node) = .empty,

    fn create(
        owner: *BlurSurface,
        kind: Kind,
        part: wlr.Box,
        state: Transform,
        duration_ms: u32,
        curve: [4]i32,
    ) !*Effect {
        const effect = try util.gpa.create(Effect);
        const now = nanoTimestamp();
        const identity: Transform = .{};
        effect.* = .{
            .owner = owner,
            .kind = kind,
            .part = part,
            .from = if (kind == .reveal) state else identity,
            .to = if (kind == .reveal) identity else state,
            .current = if (kind == .reveal) state else identity,
            .requested = now,
            .duration = @as(i128, duration_ms) * std.time.ns_per_ms,
            .curve = .{
                math.clamp(@as(f64, @floatFromInt(curve[0])) / 10000, 0, 1),
                @as(f64, @floatFromInt(curve[1])) / 10000,
                math.clamp(@as(f64, @floatFromInt(curve[2])) / 10000, 0, 1),
                @as(f64, @floatFromInt(curve[3])) / 10000,
            },
            .waiting_commit = kind == .reveal,
        };
        errdefer effect.destroy();

        if (kind == .conceal) {
            effect.takeSnapshot() catch |err| {
                log.err("cannot copy the part of the surface: {s}", .{@errorName(err)});
            };
            const count = @min(owner.current.items.len, owner.nodes.items.len);
            for (owner.current.items[0..count]) |region| {
                if (!effect.holds(region)) continue;
                const node = try util.gpa.create(Node);
                node.* = .{ .owner = owner };
                effect.ghost_nodes.append(util.gpa, node) catch |err| {
                    util.gpa.destroy(node);
                    return err;
                };
                try effect.ghosts.append(util.gpa, region);
            }
        }
        return effect;
    }

    fn destroy(effect: *Effect) void {
        if (effect.surface_node) |surface_node| {
            effect.surface_node_destroy.link.remove();
            surface_node.setOpacity(effect.surface_opacity);
            effect.surface_node = null;
        }
        effect.copy.destroy();
        for (&effect.patches) |*patch| patch.destroy();
        effect.snapshot.release();
        for (effect.ghost_nodes.items) |node| node.destroy();
        effect.ghost_nodes.deinit(util.gpa);
        effect.ghosts.deinit(util.gpa);
        util.gpa.destroy(effect);
    }

    fn handleSurfaceNodeDestroy(listener: *wl.Listener(void)) void {
        const effect: *Effect = @alignCast(@fieldParentPtr("surface_node_destroy", listener));
        effect.surface_node_destroy.link.remove();
        effect.surface_node = null;
    }

    /// Copies the part from the surface's current buffer.
    fn takeSnapshot(effect: *Effect) !void {
        const surface = effect.owner.surface;
        const client_buffer = surface.buffer orelse return;
        const texture = client_buffer.texture orelse return;
        const buffer = &client_buffer.base;
        if (surface.current.width <= 0 or surface.current.height <= 0) return;
        const kx = @as(f64, @floatFromInt(buffer.width)) / @as(f64, @floatFromInt(surface.current.width));
        const ky = @as(f64, @floatFromInt(buffer.height)) / @as(f64, @floatFromInt(surface.current.height));
        const source = scaledBox(effect.part, kx, ky);
        const width: i32 = @max(1, @as(i32, @intFromFloat(@ceil(source.width))));
        const height: i32 = @max(1, @as(i32, @intFromFloat(@ceil(source.height))));

        try effect.snapshot.ensure(width, height);
        const pass = try server.renderer.beginBufferPass(effect.snapshot.buffer.?, null);
        pass.addRect(&.{
            .box = .{ .x = 0, .y = 0, .width = effect.snapshot.capacity_width, .height = effect.snapshot.capacity_height },
            .color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
            .clip = null,
            .blend_mode = .none,
        });
        addTexture(pass, .{
            .texture = texture,
            .src_box = source,
            .dst_box = effect.snapshot.usedBox(),
            .blend_mode = .none,
            .filter_mode = .nearest,
        });
        if (!pass.submit()) return error.RenderFailed;
    }

    /// Whether [region] (a blur) is inside the part.
    fn holds(effect: *const Effect, region: Region) bool {
        const slack = 4;
        return region.x >= effect.part.x - slack and
            region.y >= effect.part.y - slack and
            region.x + region.width <= effect.part.x + effect.part.width + slack and
            region.y + region.height <= effect.part.y + effect.part.height + slack;
    }

    /// Surface-local [x, y, width, height] where the current transform puts
    /// the given surface-local rectangle.
    fn transformBox(effect: *const Effect, x: f64, y: f64, width: f64, height: f64) [4]f64 {
        const t = effect.current;
        const cx = @as(f64, @floatFromInt(effect.part.x)) + @as(f64, @floatFromInt(effect.part.width)) / 2;
        const cy = @as(f64, @floatFromInt(effect.part.y)) + @as(f64, @floatFromInt(effect.part.height)) / 2;
        return .{
            cx + (x - cx) * t.scale + t.dx,
            cy + (y - cy) * t.scale + t.dy,
            width * t.scale,
            height * t.scale,
        };
    }

    fn transformRegion(effect: *const Effect, region: Region) Region {
        const b = effect.transformBox(
            @floatFromInt(region.x),
            @floatFromInt(region.y),
            @floatFromInt(region.width),
            @floatFromInt(region.height),
        );
        const x0: i32 = @intFromFloat(@round(b[0]));
        const y0: i32 = @intFromFloat(@round(b[1]));
        const x1: i32 = @intFromFloat(@round(b[0] + b[2]));
        const y1: i32 = @intFromFloat(@round(b[1] + b[3]));
        const width = @max(1, x1 - x0);
        const height = @max(1, y1 - y0);
        var radii: [4]i32 = undefined;
        for (region.radii, &radii) |r, *out| {
            out.* = @min(
                @as(i32, @intFromFloat(@round(@as(f64, @floatFromInt(r)) * effect.current.scale))),
                @divTrunc(@min(width, height), 2),
            );
        }
        return .{
            .x = x0,
            .y = y0,
            .width = width,
            .height = height,
            .radii = radii,
            .alpha = region.alpha * @as(f32, @floatCast(math.clamp(effect.current.opacity, 0, 1))),
        };
    }

    /// The surface committed: the patches (and the copy of a reveal) follow
    /// it. A conceal stops hiding the part.
    fn committed(effect: *Effect) void {
        effect.waiting_commit = false;
        if (effect.kind == .conceal and effect.surface_node != null) effect.hiding = false;
        if (!effect.hiding) return;
        const client_buffer = effect.owner.surface.buffer orelse return;
        const buffer = &client_buffer.base;
        const damage = &effect.owner.surface.buffer_damage;
        if (effect.kind == .reveal) {
            if (effect.copy.scene_buffer) |copy| copy.setBufferWithDamage(buffer, damage);
        }
        for (&effect.patches) |*patch| {
            if (patch.scene_buffer) |scene_buffer| scene_buffer.setBufferWithDamage(buffer, damage);
        }
    }

    /// Advances the animation, right before a frame. False once it's over.
    fn step(effect: *Effect, surface_node: *wlr.SceneBuffer, now: i128) bool {
        if (effect.surface_node != surface_node) {
            // The surface got a new scene buffer (remapped): stop.
            if (effect.start != 0 or effect.surface_node != null) {
                log.debug("{s}: the surface's scene buffer changed", .{@tagName(effect.kind)});
                return false;
            }
            if (surface_node.node.parent == null) return false;
            log.debug("{s}: attached", .{@tagName(effect.kind)});
            effect.surface_node = surface_node;
            surface_node.node.events.destroy.add(&effect.surface_node_destroy);
            // 0 when another animation already hides it.
            effect.surface_opacity = if (surface_node.opacity > 0) surface_node.opacity else 1;
            surface_node.setOpacity(0);
        }

        if (effect.start == 0) {
            if (effect.waiting_commit and now - effect.requested < 80 * std.time.ns_per_ms) {
                effect.current = effect.from;
                effect.place(surface_node);
                return true;
            }
            effect.start = now;
        }
        const elapsed = now - effect.start;
        const t: f64 = if (effect.duration <= 0)
            1
        else
            math.clamp(@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(effect.duration)), 0, 1);
        if (t >= 1) return false;
        const c = effect.curve;
        effect.current = Transform.lerp(effect.from, effect.to, cubicBezier(c[0], c[1], c[2], c[3], t));
        effect.place(surface_node);
        return true;
    }

    /// Positions the copy (and the patches) for the current transform.
    fn place(effect: *Effect, surface_node: *wlr.SceneBuffer) void {
        const parent = surface_node.node.parent orelse return;
        const base_x = surface_node.node.x;
        const base_y = surface_node.node.y;

        if (!effect.hiding) {
            for (&effect.patches) |*patch| patch.destroy();
            if (surface_node.opacity != effect.surface_opacity) surface_node.setOpacity(effect.surface_opacity);
        } else {
            // wlroots sets the opacity of a surface's scene buffer on every
            // commit (alpha modifier): hide it again before each frame.
            if (surface_node.opacity != 0) surface_node.setOpacity(0);
            const live = surface_node.buffer orelse return;
            const live_width = effect.owner.surface.current.width;
            const live_height = effect.owner.surface.current.height;
            if (live_width <= 0 or live_height <= 0) return;
            const live_kx = @as(f64, @floatFromInt(live.width)) / @as(f64, @floatFromInt(live_width));
            const live_ky = @as(f64, @floatFromInt(live.height)) / @as(f64, @floatFromInt(live_height));
            const p = effect.part;
            const rects = [4]wlr.Box{
                .{ .x = 0, .y = 0, .width = live_width, .height = p.y },
                .{ .x = 0, .y = p.y + p.height, .width = live_width, .height = live_height - p.y - p.height },
                .{ .x = 0, .y = p.y, .width = p.x, .height = p.height },
                .{ .x = p.x + p.width, .y = p.y, .width = live_width - p.x - p.width, .height = p.height },
            };
            for (&effect.patches, rects) |*patch, rect| {
                if (rect.width <= 0 or rect.height <= 0) {
                    patch.destroy();
                    continue;
                }
                const scene_buffer = patch.get(parent) orelse continue;
                if (scene_buffer.buffer != live) scene_buffer.setBuffer(live);
                scene_buffer.node.placeAbove(&surface_node.node);
                scene_buffer.setSourceBox(&scaledBox(rect, live_kx, live_ky));
                scene_buffer.setTransform(surface_node.transform);
                scene_buffer.node.setPosition(base_x + rect.x, base_y + rect.y);
                scene_buffer.setDestSize(rect.width, rect.height);
            }
        }

        // What the copy shows: the part of the live buffer (reveal) or the
        // snapshot (conceal).
        const buffer: *wlr.Buffer, const source: wlr.FBox = switch (effect.kind) {
            .reveal => blk: {
                const live = surface_node.buffer orelse return;
                const width = effect.owner.surface.current.width;
                const height = effect.owner.surface.current.height;
                if (width <= 0 or height <= 0) return;
                break :blk .{ live, scaledBox(
                    effect.part,
                    @as(f64, @floatFromInt(live.width)) / @as(f64, @floatFromInt(width)),
                    @as(f64, @floatFromInt(live.height)) / @as(f64, @floatFromInt(height)),
                ) };
            },
            .conceal => .{ effect.snapshot.buffer orelse return, .{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(effect.snapshot.width),
                .height = @floatFromInt(effect.snapshot.height),
            } },
        };
        const copy = effect.copy.get(parent) orelse return;
        if (copy.buffer != buffer) copy.setBuffer(buffer);
        copy.node.placeAbove(&surface_node.node);
        for (&effect.patches) |*patch| {
            if (patch.scene_buffer) |scene_buffer| copy.node.placeAbove(&scene_buffer.node);
        }
        copy.setSourceBox(&source);
        if (effect.kind == .reveal) copy.setTransform(surface_node.transform);
        const b = effect.transformBox(
            @floatFromInt(effect.part.x),
            @floatFromInt(effect.part.y),
            @floatFromInt(effect.part.width),
            @floatFromInt(effect.part.height),
        );
        const x0: i32 = @intFromFloat(@round(b[0]));
        const y0: i32 = @intFromFloat(@round(b[1]));
        const x1: i32 = @intFromFloat(@round(b[0] + b[2]));
        const y1: i32 = @intFromFloat(@round(b[1] + b[3]));
        copy.node.setPosition(base_x + x0, base_y + y0);
        copy.setDestSize(@max(1, x1 - x0), @max(1, y1 - y0));
        const opacity: f32 = @floatCast(math.clamp(effect.current.opacity, 0, 1));
        copy.setOpacity(opacity);
        copy.node.setEnabled(opacity > 0.002);
    }
};

fn scaledBox(box: wlr.Box, kx: f64, ky: f64) wlr.FBox {
    return .{
        .x = @as(f64, @floatFromInt(box.x)) * kx,
        .y = @as(f64, @floatFromInt(box.y)) * ky,
        .width = @as(f64, @floatFromInt(box.width)) * kx,
        .height = @as(f64, @floatFromInt(box.height)) * ky,
    };
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

    const sample = struct {
        fn f(a: f64, b: f64, c: f64, u: f64) f64 {
            return ((a * u + b) * u + c) * u;
        }
    }.f;

    // Bisection: x(u) is monotonic for x1, x2 in [0, 1].
    var lo: f64 = 0;
    var hi: f64 = 1;
    var u = t;
    var i: usize = 0;
    while (i < 40) : (i += 1) {
        const x = sample(ax, bx, cx, u);
        if (@abs(x - t) < 1e-7) break;
        if (x < t) lo = u else hi = u;
        u = (lo + hi) / 2;
    }
    return sample(ay, by, cy, u);
}

/// A buffer the blur renders into, possibly larger than what is used so that
/// animated regions don't reallocate every frame.
const Target = struct {
    buffer: ?*wlr.Buffer = null,
    texture: ?*wlr.Texture = null,
    capacity_width: i32 = 0,
    capacity_height: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,

    fn ensure(target: *Target, width: i32, height: i32) !void {
        target.width = width;
        target.height = height;
        // Reuse a buffer that fits without wasting too much memory.
        if (target.buffer != null and
            width <= target.capacity_width and height <= target.capacity_height and
            target.capacity_width <= 2 * roundUp(width, 32) and
            target.capacity_height <= 2 * roundUp(height, 32))
        {
            return;
        }
        target.release();

        const capacity_width = roundUp(width, 32);
        const capacity_height = roundUp(height, 32);
        var modifier: u64 = 0x00ffffffffffffff; // DRM_FORMAT_MOD_INVALID: implicit
        const format: wlr.DrmFormat = .{
            .format = 0x34325241, // DRM_FORMAT_ARGB8888
            .len = 1,
            .capacity = 1,
            .modifiers = @ptrCast(&modifier),
        };
        const buffer = server.allocator.createBuffer(capacity_width, capacity_height, &format) orelse
            return error.BufferCreateFailed;
        errdefer buffer.drop();
        const texture = wlr.Texture.fromBuffer(server.renderer, buffer) orelse
            return error.TextureCreateFailed;
        target.buffer = buffer;
        target.texture = texture;
        target.capacity_width = capacity_width;
        target.capacity_height = capacity_height;
    }

    fn release(target: *Target) void {
        if (target.texture) |texture| texture.destroy();
        if (target.buffer) |buffer| buffer.drop();
        target.texture = null;
        target.buffer = null;
        target.capacity_width = 0;
        target.capacity_height = 0;
    }

    fn usedBox(target: *const Target) wlr.Box {
        return .{ .x = 0, .y = 0, .width = target.width, .height = target.height };
    }
};

fn roundUp(value: i32, multiple: i32) i32 {
    return @divTrunc(value + multiple - 1, multiple) * multiple;
}

/// Mirrors wlr_render_texture_options, with the color management pointers
/// nullable as in C (the GLES2 renderer ignores them).
const TextureOptions = extern struct {
    texture: *wlr.Texture,
    src_box: wlr.FBox,
    dst_box: wlr.Box,
    alpha: ?*const f32 = null,
    clip: ?*const pixman.Region32 = null,
    transform: wl.Output.Transform = .normal,
    filter_mode: wlr.RenderPass.ScaleFilterMode = .bilinear,
    blend_mode: wlr.RenderPass.BlendMode = .premultiplied,
    transfer_function: wlr.color.TransferFunction = .srgb,
    primaries: ?*const anyopaque = null,
    color_encoding: wlr.color.Encoding = .none,
    color_range: wlr.color.Range = .none,
    luminance_multiplier: ?*const f32 = null,
    wait_timeline: ?*wlr.DrmSyncobjTimeline = null,
    wait_point: u64 = 0,
};

fn addTexture(pass: *wlr.RenderPass, options: TextureOptions) void {
    pass.addTexture(@ptrCast(&options));
}

const Node = struct {
    owner: *BlurSurface,
    scene_buffer: ?*wlr.SceneBuffer = null,
    /// The scene buffer goes away with the tree of its surface, which may be
    /// destroyed before the surface.
    scene_buffer_destroy: wl.Listener(void) = .init(handleSceneBufferDestroy),
    /// base, then the downsampled levels
    levels: [max_levels + 1]Target = @splat(.{}),
    output: Target = .{},
    signature: u64 = 0,
    generation: u64 = 1,
    logical_width: i32 = 0,
    logical_height: i32 = 0,

    fn reset(node: *Node) void {
        if (node.scene_buffer) |scene_buffer| scene_buffer.setBuffer(null);
        for (&node.levels) |*level| level.release();
        node.output.release();
        node.signature = 0;
    }

    fn destroy(node: *Node) void {
        node.reset();
        if (node.scene_buffer) |scene_buffer| {
            node.forget();
            scene_buffer.node.destroy();
        }
        util.gpa.destroy(node);
    }

    fn handleSceneBufferDestroy(listener: *wl.Listener(void)) void {
        const node: *Node = @fieldParentPtr("scene_buffer_destroy", listener);
        node.forget();
    }

    /// Lets go of the scene buffer (a new one is made when needed).
    fn forget(node: *Node) void {
        const scene_buffer = node.scene_buffer orelse return;
        node.scene_buffer_destroy.link.remove();
        _ = server.blur.nodes.remove(scene_buffer);
        node.scene_buffer = null;
        node.signature = 0;
    }

    fn update(node: *Node, region: Region, update_: Update, below: []const Item, scale: f32) void {
        const surface_node = &update_.scene_buffer.node;
        const parent = surface_node.parent orelse return;

        // Keep the blur right below its surface.
        const scene_buffer = node.scene_buffer orelse blk: {
            const scene_buffer = parent.createSceneBuffer(null) catch {
                log.err("out of memory", .{});
                return;
            };
            scene_buffer.point_accepts_input = rejectInput;
            server.blur.nodes.put(util.gpa, scene_buffer, node) catch {
                scene_buffer.node.destroy();
                log.err("out of memory", .{});
                return;
            };
            node.scene_buffer = scene_buffer;
            scene_buffer.node.events.destroy.add(&node.scene_buffer_destroy);
            break :blk scene_buffer;
        };
        // Faded out completely (by an animation).
        scene_buffer.node.setEnabled(region.alpha > 0.002);
        if (!scene_buffer.node.enabled) return;
        if (region.cutout != null) {
            // Above the window this surface lies below.
            const window_tree, const ox, const oy = windowTreeOf(surface_node) orelse {
                scene_buffer.node.setEnabled(false);
                return;
            };
            if (scene_buffer.node.parent != window_tree) scene_buffer.node.reparent(window_tree);
            scene_buffer.node.raiseToTop();
            scene_buffer.node.setPosition(ox + region.x, oy + region.y);
        } else {
            if (scene_buffer.node.parent != parent) scene_buffer.node.reparent(parent);
            scene_buffer.node.placeBelow(surface_node);
            scene_buffer.node.setPosition(surface_node.x + region.x, surface_node.y + region.y);
        }
        scene_buffer.setDestSize(region.width, region.height);
        node.logical_width = region.width;
        node.logical_height = region.height;

        const box: wlr.Box = .{
            .x = update_.x + region.x,
            .y = update_.y + region.y,
            .width = region.width,
            .height = region.height,
        };

        // Blurs read around themselves; cutouts only their corner.
        const area = if (region.cutout != null) box else readArea(box);

        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, box);
        std.hash.autoHash(&hasher, area);
        std.hash.autoHash(&hasher, region.radii);
        std.hash.autoHash(&hasher, @as(u32, @bitCast(region.alpha)));
        std.hash.autoHash(&hasher, @as(u32, @bitCast(scale)));
        for (below) |item| {
            if (!intersects(item.box, area)) continue;
            if (item.kind == .blur and item.kind.blur.owner == node.owner) continue;
            std.hash.autoHash(&hasher, item.box);
            std.hash.autoHash(&hasher, item.key);
        }
        const signature = hasher.final() | 1;
        if (signature == node.signature) return;

        const rendered = if (region.cutout != null)
            NodeCutout.render(node, region, box, below, scale)
        else
            node.render(region, box, area, below, scale);
        rendered catch |err| {
            log.err("blur failed: {s}", .{@errorName(err)});
            node.reset();
            return;
        };
        node.signature = signature;
        node.generation +%= 1;

        var damage: pixman.Region32 = undefined;
        damage.initRect(0, 0, @intCast(node.output.width), @intCast(node.output.height));
        defer damage.deinit();
        scene_buffer.setBufferWithDamage(node.output.buffer.?, &damage);
        scene_buffer.setSourceBox(&.{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(node.output.width),
            .height = @floatFromInt(node.output.height),
        });
    }

    fn render(node: *Node, region: Region, box: wlr.Box, area: wlr.Box, below: []const Item, scale: f32) !void {
        const physical_width: i32 = @max(1, @as(i32, @intFromFloat(@ceil(@as(f32, @floatFromInt(box.width)) * scale))));
        const physical_height: i32 = @max(1, @as(i32, @intFromFloat(@ceil(@as(f32, @floatFromInt(box.height)) * scale))));
        const area_width: i32 = @max(1, @as(i32, @intFromFloat(@ceil(@as(f32, @floatFromInt(area.width)) * scale))));
        const area_height: i32 = @max(1, @as(i32, @intFromFloat(@ceil(@as(f32, @floatFromInt(area.height)) * scale))));

        // Everything below the area read, at half resolution.
        const base = &node.levels[0];
        try base.ensure(@max(1, @divTrunc(area_width, 2)), @max(1, @divTrunc(area_height, 2)));
        {
            const pass = try server.renderer.beginBufferPass(base.buffer.?, null);
            pass.addRect(&.{
                .box = base.usedBox(),
                .color = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
                .clip = null,
                .blend_mode = .none,
            });
            const kx = @as(f64, @floatFromInt(base.width)) / @as(f64, @floatFromInt(area.width));
            const ky = @as(f64, @floatFromInt(base.height)) / @as(f64, @floatFromInt(area.height));
            for (below) |item| {
                if (!intersects(item.box, area)) continue;
                const x0 = @round(@as(f64, @floatFromInt(item.box.x - area.x)) * kx);
                const y0 = @round(@as(f64, @floatFromInt(item.box.y - area.y)) * ky);
                const x1 = @round(@as(f64, @floatFromInt(item.box.x + item.box.width - area.x)) * kx);
                const y1 = @round(@as(f64, @floatFromInt(item.box.y + item.box.height - area.y)) * ky);
                const dst: wlr.Box = .{
                    .x = @intFromFloat(x0),
                    .y = @intFromFloat(y0),
                    .width = @max(1, @as(i32, @intFromFloat(x1 - x0))),
                    .height = @max(1, @as(i32, @intFromFloat(y1 - y0))),
                };
                switch (item.kind) {
                    .rect => |rect| pass.addRect(&.{
                        .box = dst,
                        .color = .{ .r = rect.color[0], .g = rect.color[1], .b = rect.color[2], .a = rect.color[3] },
                        .clip = null,
                        .blend_mode = .premultiplied,
                    }),
                    .blur => |other| {
                        if (other.owner == node.owner) continue;
                        const texture = other.output.texture orelse continue;
                        addTexture(pass, .{
                            .texture = texture,
                            .src_box = fullBox(&other.output),
                            .dst_box = dst,
                        });
                    },
                    .buffer => |scene_buffer| {
                        if (scene_buffer.private.is_single_pixel_buffer) {
                            const c = scene_buffer.private.single_pixel_buffer_color;
                            const max: f32 = @floatFromInt(math.maxInt(u32));
                            pass.addRect(&.{
                                .box = dst,
                                .color = .{
                                    .r = @as(f32, @floatFromInt(c[0])) / max * scene_buffer.opacity,
                                    .g = @as(f32, @floatFromInt(c[1])) / max * scene_buffer.opacity,
                                    .b = @as(f32, @floatFromInt(c[2])) / max * scene_buffer.opacity,
                                    .a = @as(f32, @floatFromInt(c[3])) / max * scene_buffer.opacity,
                                },
                                .clip = null,
                                .blend_mode = .premultiplied,
                            });
                            continue;
                        }
                        const texture = textureOf(scene_buffer) orelse continue;
                        addTexture(pass, .{
                            .texture = texture,
                            .src_box = scene_buffer.src_box,
                            .dst_box = dst,
                            .alpha = &scene_buffer.opacity,
                            .transform = scene_buffer.transform,
                        });
                    },
                }
            }
            if (!pass.submit()) return error.RenderFailed;
        }

        // Halve until the image is small: each level averages the previous
        // one, the radius of the blur doubles.
        var levels: usize = 1;
        while (levels <= max_levels) : (levels += 1) {
            const previous = &node.levels[levels - 1];
            const width = @divTrunc(previous.width, 2);
            const height = @divTrunc(previous.height, 2);
            if (width < 4 or height < 4) break;
            const level = &node.levels[levels];
            try level.ensure(width, height);
            try blit(previous, level, false);
        }
        // Then back up through the same sizes, which smooths the blocks.
        var level = levels - 1;
        while (level > 0) : (level -= 1) {
            try blit(&node.levels[level], &node.levels[level - 1], true);
        }

        // Clipped to the rounded rectangle, at full resolution so that the
        // corners are as smooth as the panel drawn above.
        try node.output.ensure(physical_width, physical_height);
        var clip: pixman.Region32 = undefined;
        clip.init();
        defer clip.deinit();
        var radii: [4]f64 = undefined;
        for (region.radii, &radii) |r, *out| out.* = @as(f64, @floatFromInt(r)) * scale;
        roundedRegion(&clip, physical_width, physical_height, radii);
        const pass = try server.renderer.beginBufferPass(node.output.buffer.?, null);
        pass.addRect(&.{
            .box = .{ .x = 0, .y = 0, .width = node.output.capacity_width, .height = node.output.capacity_height },
            .color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
            .clip = null,
            .blend_mode = .none,
        });
        // The region's part of the area read.
        const kx = @as(f64, @floatFromInt(base.width)) / @as(f64, @floatFromInt(area.width));
        const ky = @as(f64, @floatFromInt(base.height)) / @as(f64, @floatFromInt(area.height));
        addTexture(pass, .{
            .texture = base.texture.?,
            .src_box = .{
                .x = @as(f64, @floatFromInt(box.x - area.x)) * kx,
                .y = @as(f64, @floatFromInt(box.y - area.y)) * ky,
                .width = @as(f64, @floatFromInt(box.width)) * kx,
                .height = @as(f64, @floatFromInt(box.height)) * ky,
            },
            .dst_box = node.output.usedBox(),
            .alpha = &region.alpha,
            .clip = &clip,
        });
        if (server.blur.noiseTexture()) |noise| {
            var y: i32 = 0;
            while (y < physical_height) : (y += noise_size) {
                var x: i32 = 0;
                while (x < physical_width) : (x += noise_size) {
                    addTexture(pass, .{
                        .texture = noise,
                        .src_box = .{ .x = 0, .y = 0, .width = noise_size, .height = noise_size },
                        .dst_box = .{ .x = x, .y = y, .width = noise_size, .height = noise_size },
                        .alpha = &region.alpha,
                        .clip = &clip,
                    });
                }
            }
        }
        if (!pass.submit()) return error.RenderFailed;
    }
};

/// The tree of the window [node] (a decoration surface) belongs to, and
/// where [node]'s parent is in it.
fn windowTreeOf(node: *wlr.SceneNode) ?struct { *wlr.SceneTree, i32, i32 } {
    var x: i32 = 0;
    var y: i32 = 0;
    var tree = node.parent orelse return null;
    while (true) {
        // The data attached to this very tree (fromNode would find the
        // nearest ancestor's).
        if (@as(?*SceneNodeData, @ptrCast(@alignCast(tree.node.data)))) |data| {
            if (data.node == &tree.node and data.data == .window) return .{ tree, x, y };
        }
        x += tree.node.x;
        y += tree.node.y;
        tree = tree.node.parent orelse return null;
    }
}

const NodeCutout = struct {
    /// What is behind the window at a corner (the window excluded), only
    /// outside the corner's arc: drawn above the window, it looks rounded.
    /// Pixels the arc crosses are drawn with the part of them outside it as
    /// opacity, so the corner is smooth.
    fn render(node: *Node, region: Region, box: wlr.Box, below: []const Item, scale: f32) !void {
        const width: i32 = @max(1, @as(i32, @intFromFloat(@ceil(@as(f32, @floatFromInt(box.width)) * scale))));
        const height: i32 = @max(1, @as(i32, @intFromFloat(@ceil(@as(f32, @floatFromInt(box.height)) * scale))));

        // What's behind, unclipped.
        const behind = &node.levels[0];
        try behind.ensure(width, height);
        {
            const pass = try server.renderer.beginBufferPass(behind.buffer.?, null);
            pass.addRect(&.{
                .box = behind.usedBox(),
                .color = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
                .clip = null,
                .blend_mode = .none,
            });
            const kx = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(box.width));
            const ky = @as(f64, @floatFromInt(height)) / @as(f64, @floatFromInt(box.height));
            for (below) |item| {
                if (!intersects(item.box, box)) continue;
                const x0 = @round(@as(f64, @floatFromInt(item.box.x - box.x)) * kx);
                const y0 = @round(@as(f64, @floatFromInt(item.box.y - box.y)) * ky);
                const x1 = @round(@as(f64, @floatFromInt(item.box.x + item.box.width - box.x)) * kx);
                const y1 = @round(@as(f64, @floatFromInt(item.box.y + item.box.height - box.y)) * ky);
                const dst: wlr.Box = .{
                    .x = @intFromFloat(x0),
                    .y = @intFromFloat(y0),
                    .width = @max(1, @as(i32, @intFromFloat(x1 - x0))),
                    .height = @max(1, @as(i32, @intFromFloat(y1 - y0))),
                };
                switch (item.kind) {
                    .rect => |rect| pass.addRect(&.{
                        .box = dst,
                        .color = .{ .r = rect.color[0], .g = rect.color[1], .b = rect.color[2], .a = rect.color[3] },
                        .clip = null,
                        .blend_mode = .premultiplied,
                    }),
                    .blur => |other| {
                        if (other.owner == node.owner) continue;
                        const texture = other.output.texture orelse continue;
                        addTexture(pass, .{
                            .texture = texture,
                            .src_box = fullBox(&other.output),
                            .dst_box = dst,
                        });
                    },
                    .buffer => |scene_buffer| {
                        if (scene_buffer.private.is_single_pixel_buffer) {
                            const c = scene_buffer.private.single_pixel_buffer_color;
                            const max: f32 = @floatFromInt(math.maxInt(u32));
                            pass.addRect(&.{
                                .box = dst,
                                .color = .{
                                    .r = @as(f32, @floatFromInt(c[0])) / max * scene_buffer.opacity,
                                    .g = @as(f32, @floatFromInt(c[1])) / max * scene_buffer.opacity,
                                    .b = @as(f32, @floatFromInt(c[2])) / max * scene_buffer.opacity,
                                    .a = @as(f32, @floatFromInt(c[3])) / max * scene_buffer.opacity,
                                },
                                .clip = null,
                                .blend_mode = .premultiplied,
                            });
                            continue;
                        }
                        const texture = textureOf(scene_buffer) orelse continue;
                        addTexture(pass, .{
                            .texture = texture,
                            .src_box = scene_buffer.src_box,
                            .dst_box = dst,
                            .alpha = &scene_buffer.opacity,
                            .transform = scene_buffer.transform,
                        });
                    },
                }
            }
            if (!pass.submit()) return error.RenderFailed;
        }

        // Then outside the arc only.
        try node.output.ensure(width, height);
        const corner = region.cutout.?;
        const radius = @as(f64, @floatFromInt(region.radii[corner])) * scale;
        var outside: pixman.Region32 = undefined;
        outside.init();
        defer outside.deinit();
        const pass = try server.renderer.beginBufferPass(node.output.buffer.?, null);
        pass.addRect(&.{
            .box = .{ .x = 0, .y = 0, .width = node.output.capacity_width, .height = node.output.capacity_height },
            .color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
            .clip = null,
            .blend_mode = .none,
        });
        const texture = behind.texture.?;
        var row: i32 = 0;
        while (row < height) : (row += 1) {
            var col: i32 = 0;
            while (col < width) : (col += 1) {
                const coverage = outsideCoverage(radius, col, row);
                if (coverage <= 0.004) continue;
                // Rows and columns count from the corner.
                const x = if (corner == 0 or corner == 3) col else width - 1 - col;
                const y = if (corner == 0 or corner == 1) row else height - 1 - row;
                if (coverage >= 0.996) {
                    _ = outside.unionRect(&outside, x, y, 1, 1);
                    continue;
                }
                const alpha: f32 = @floatCast(coverage);
                addTexture(pass, .{
                    .texture = texture,
                    .src_box = .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = 1, .height = 1 },
                    .dst_box = .{ .x = x, .y = y, .width = 1, .height = 1 },
                    .alpha = &alpha,
                    .blend_mode = .none,
                    .filter_mode = .nearest,
                });
            }
        }
        addTexture(pass, .{
            .texture = texture,
            .src_box = .{ .x = 0, .y = 0, .width = @floatFromInt(width), .height = @floatFromInt(height) },
            .dst_box = .{ .x = 0, .y = 0, .width = width, .height = height },
            .clip = &outside,
            .blend_mode = .none,
            .filter_mode = .nearest,
        });
        if (!pass.submit()) return error.RenderFailed;
    }

    /// How much of pixel [col], [row] (counted from the corner) lies outside
    /// the arc of a corner of [radius]: 4 × 4 samples.
    fn outsideCoverage(radius: f64, col: i32, row: i32) f64 {
        var outside: u32 = 0;
        var sy: u32 = 0;
        while (sy < 4) : (sy += 1) {
            var sx: u32 = 0;
            while (sx < 4) : (sx += 1) {
                const px = @as(f64, @floatFromInt(col)) + (@as(f64, @floatFromInt(sx)) + 0.5) / 4;
                const py = @as(f64, @floatFromInt(row)) + (@as(f64, @floatFromInt(sy)) + 0.5) / 4;
                if (px >= radius or py >= radius) continue;
                const dx = radius - px;
                const dy = radius - py;
                if (dx * dx + dy * dy > radius * radius) outside += 1;
            }
        }
        return @as(f64, @floatFromInt(outside)) / 16;
    }
};

fn blit(source: *Target, destination: *Target, upsample: bool) !void {
    const pass = try server.renderer.beginBufferPass(destination.buffer.?, null);
    addTexture(pass, .{
        .texture = source.texture.?,
        // When enlarging, bilinear filtering at the edge would also sample the
        // unused part of an oversized buffer.
        .src_box = if (upsample) insetBox(source) else fullBox(source),
        .dst_box = destination.usedBox(),
        .blend_mode = .none,
    });
    if (!pass.submit()) return error.RenderFailed;
}

fn fullBox(target: *const Target) wlr.FBox {
    return .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(target.width),
        .height = @floatFromInt(target.height),
    };
}

fn insetBox(target: *const Target) wlr.FBox {
    const width: f64 = @floatFromInt(target.width);
    const height: f64 = @floatFromInt(target.height);
    return .{
        .x = 0.5,
        .y = 0.5,
        .width = @max(0.5, width - 1),
        .height = @max(0.5, height - 1),
    };
}

/// The texture the scene draws a buffer node with, if there is one yet.
fn textureOf(scene_buffer: *wlr.SceneBuffer) ?*wlr.Texture {
    if (scene_buffer.private.texture) |texture| {
        if (ownTexture(texture)) return texture;
    }
    const buffer = scene_buffer.buffer orelse return null;
    if (wlr.ClientBuffer.get(buffer)) |client_buffer| {
        if (client_buffer.texture) |texture| {
            if (ownTexture(texture)) return texture;
        }
    }
    return null;
}

/// struct wlr_texture, with the renderer zig-wlroots leaves out.
const TextureFields = extern struct {
    impl: *const anyopaque,
    width: u32,
    height: u32,
    renderer: ?*wlr.Renderer,
};

/// Whether [texture] belongs to the current renderer: after a GPU reset
/// (NVIDIA reports one on resume) scene buffers still hold textures of the
/// one destroyed until their surfaces commit again, and drawing them
/// breaks the blur.
fn ownTexture(texture: *wlr.Texture) bool {
    const fields: *const TextureFields = @ptrCast(@alignCast(texture));
    return fields.renderer == server.renderer;
}

fn intersects(a: wlr.Box, b: wlr.Box) bool {
    return a.x < b.x + b.width and b.x < a.x + a.width and
        a.y < b.y + b.height and b.y < a.y + a.height;
}

/// A rounded rectangle as rows of rectangles, one per pixel row in the
/// corners. [radii]: top left, top right, bottom right, bottom left.
fn roundedRegion(region: *pixman.Region32, width: i32, height: i32, radii: [4]f64) void {
    const half = @divTrunc(height, 2);
    const top_rows: i32 = @min(half, @as(i32, @intFromFloat(@ceil(@max(radii[0], radii[1])))));
    const bottom_rows: i32 = @min(half, @as(i32, @intFromFloat(@ceil(@max(radii[2], radii[3])))));
    const middle = height - top_rows - bottom_rows;
    if (middle > 0) {
        _ = region.unionRect(region, 0, top_rows, @intCast(width), @intCast(middle));
    }
    var row: i32 = 0;
    while (row < top_rows) : (row += 1) {
        const left = cornerInset(radii[0], row);
        const right = cornerInset(radii[1], row);
        if (width - left - right > 0) {
            _ = region.unionRect(region, left, row, @intCast(width - left - right), 1);
        }
    }
    row = 0;
    while (row < bottom_rows) : (row += 1) {
        const left = cornerInset(radii[3], row);
        const right = cornerInset(radii[2], row);
        if (width - left - right > 0) {
            _ = region.unionRect(region, left, height - 1 - row, @intCast(width - left - right), 1);
        }
    }
}

/// How far row [row] (counted from the edge) of a corner of radius [radius]
/// starts from the side.
fn cornerInset(radius: f64, row: i32) i32 {
    if (radius <= 0 or @as(f64, @floatFromInt(row)) >= radius) return 0;
    const dy = radius - (@as(f64, @floatFromInt(row)) + 0.5);
    const dx = @sqrt(@max(0, radius * radius - dy * dy));
    return @intFromFloat(@round(radius - dx));
}

fn rejectInput(_: *wlr.SceneBuffer, _: *f64, _: *f64) callconv(.c) bool {
    return false;
}
