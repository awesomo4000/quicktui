const std = @import("std");
const dither = @import("dither3d.zig");
pub const width = 240;
pub const height = 160;
pub const byte_count = width * height * 4;
pub const Scene = struct { shape: u32 = 0, angle: f64 = 0, tilt: f32 = 0.7, zoom: f32 = 0.82, wire: bool = false, palette: u32 = 0, playing: bool = true, fps: u32 = 10, rotation_speed: f32 = 1, epoch: u32 = 0, charset: u32 = 0, cols: u32 = 60, rows: u32 = 20, tone: u32 = 0, wash_strength: f32 = 0.3, dark_ink: f32 = 0.15, brightness: f32 = 0, contrast: f32 = 1, dot_scale: f32 = 4, fractal_zoom: f64 = 1, center_x: f64 = -0.65, center_y: f64 = 0 };
const V = struct { x: f32, y: f32, z: f32, wx: f32, wy: f32, uv: dither.UV = .{ 0, 0 }, inv_w: f32 = 1 };
fn f(n: anytype) f32 {
    return @floatFromInt(n);
}
fn byte(n: f32) u8 {
    return @intFromFloat(@max(0, @min(255, n)));
}
pub const Raster = struct {
    pixels: [byte_count]u8 = undefined,
    depth: [width * height]f32 = undefined,
    wash: [width * height][4]f32 = undefined,
    fn pixel(self: *Raster, x: i32, y: i32, z: f32, color: [3]u8) void {
        if (x < 0 or y < 0 or x >= width or y >= height) return;
        const k: usize = @intCast(y * width + x);
        if (z < self.depth[k]) return;
        self.depth[k] = z;
        @memcpy(self.pixels[k * 4 ..][0..3], &color);
    }
    fn line(self: *Raster, a: V, b: V, color: [3]u8) void {
        const n: usize = @intFromFloat(@ceil(@max(@abs(b.x - a.x), @abs(b.y - a.y))));
        for (0..n + 1) |i| {
            const t = if (n == 0) 0 else f(i) / f(n);
            self.pixel(@intFromFloat(@round(a.x + (b.x - a.x) * t)), @intFromFloat(@round(a.y + (b.y - a.y) * t)), a.z + (b.z - a.z) * t, color);
        }
    }
    fn toned(scene: Scene, color: [3]u8, x: i32, y: i32, uv: dither.PreciseUV, dx: dither.UV, dy: dither.UV) [3]u8 {
        var rgb: [3]u8 = undefined;
        for (color, 0..) |c, i| rgb[i] = byte(((@as(f32, @floatFromInt(c)) / 255 - 0.5) * scene.contrast + 0.5 + scene.brightness) * 255);
        if (scene.tone == 0) return rgb;
        const light = (f(rgb[0]) * 0.299 + f(rgb[1]) * 0.587 + f(rgb[2]) * 0.114) / 255;
        if (scene.tone == 1) return @splat(byte(light * 255));
        if (scene.tone == 3 or scene.tone == 4 or (scene.tone == 5 or scene.tone == 6)) {
            const ink = dither.shade(uv, dx, dy, light, scene.dot_scale);
            if (scene.tone == 3 or (scene.tone == 5 or scene.tone == 6) or ink == 0) return @splat(ink);
            // Preserve the exact luminance-driven coverage, tinting only lit dots.
            // Normalize ink intensity so color is not shaded twice by coverage.
            const peak = @max(rgb[0], rgb[1], rgb[2], 1);
            for (&rgb) |*channel| channel.* = byte(f(channel.*) * 255 / f(peak));
            return rgb;
        }
        const bayer = [16]u8{ 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
        const i: usize = @intCast(@mod(y, 4) * 4 + @mod(x, 4));
        return @splat(if (light > (f(bayer[i]) + 0.5) / 16) @as(u8, 255) else 0);
    }
    fn uvAt(a: V, b: V, c: V, w1: f32, w2: f32) dither.UV {
        const w3 = 1 - w1 - w2;
        const denominator = w1 * a.inv_w + w2 * b.inv_w + w3 * c.inv_w;
        return (a.uv * @as(dither.UV, @splat(w1 * a.inv_w)) + b.uv * @as(dither.UV, @splat(w2 * b.inv_w)) + c.uv * @as(dither.UV, @splat(w3 * c.inv_w))) / @as(dither.UV, @splat(denominator));
    }
    fn triangle(self: *Raster, a: V, b: V, c: V, index: usize, scene: Scene) void {
        const ux = b.wx - a.wx;
        const uy = b.wy - a.wy;
        const uz = b.z - a.z;
        const vx = c.wx - a.wx;
        const vy = c.wy - a.wy;
        const vz = c.z - a.z;
        const nx = uy * vz - uz * vy;
        const ny = uz * vx - ux * vz;
        const nz = ux * vy - uy * vx;
        const len = @max(0.000001, @sqrt(nx * nx + ny * ny + nz * nz));
        const light = 0.18 + 0.82 * @abs((nx * 0.3 + ny * 0.5 + nz * 0.81) / len);
        const palette = [3][3]f32{ .{ 75, 208, 186 }, .{ 225, 151, 86 }, .{ 160, 131, 229 } };
        const base = palette[(scene.palette + index / 180) % 3];
        const shine = std.math.pow(f32, @abs(nz) / len, 16) * 48;
        const color = [3]u8{ byte(base[0] * light + shine), byte(base[1] * light + shine), byte(base[2] * light + shine) };
        if (scene.wire) {
            self.line(a, b, toned(scene, color, 0, 0, a.uv, .{ 0.02, 0 }, .{ 0, 0.02 }));
            self.line(b, c, toned(scene, color, 0, 0, b.uv, .{ 0.02, 0 }, .{ 0, 0.02 }));
            return;
        }
        const den = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y);
        if (@abs(den) < 0.01) return;
        const min_x: i32 = @intFromFloat(@max(0, @floor(@min(a.x, @min(b.x, c.x)))));
        const max_x: i32 = @intFromFloat(@min(width - 1, @ceil(@max(a.x, @max(b.x, c.x)))));
        const min_y: i32 = @intFromFloat(@max(0, @floor(@min(a.y, @min(b.y, c.y)))));
        const max_y: i32 = @intFromFloat(@min(height - 1, @ceil(@max(a.y, @max(b.y, c.y)))));
        var y = min_y;
        while (y <= max_y) : (y += 1) {
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const w1 = ((b.y - c.y) * (f(x) - c.x) + (c.x - b.x) * (f(y) - c.y)) / den;
                const w2 = ((c.y - a.y) * (f(x) - c.x) + (a.x - c.x) * (f(y) - c.y)) / den;
                const w3 = 1 - w1 - w2;
                if (w1 >= 0 and w2 >= 0 and w3 >= 0) {
                    const uv = uvAt(a, b, c, w1, w2);
                    const dx = uvAt(a, b, c, w1 + (b.y - c.y) / den, w2 + (c.y - a.y) / den) - uv;
                    const dy = uvAt(a, b, c, w1 + (c.x - b.x) / den, w2 + (a.x - c.x) / den) - uv;
                    if ((scene.tone == 5 or scene.tone == 6)) self.addWash(@intCast(x), @intCast(y), color, w1 * a.z + w2 * b.z + w3 * c.z);
                    self.pixel(x, y, w1 * a.z + w2 * b.z + w3 * c.z, toned(scene, color, x, y, uv, dx, dy));
                }
            }
        }
    }
    fn addWash(self: *Raster, x: usize, y: usize, color: [3]u8, z: f32) void {
        // Color collects ALL projected faces, independently of the depth-tested mask.
        const weight = @exp(@max(-8, @min(8, z * 0.2)));
        const peak = f(@max(color[0], color[1], color[2], 1));
        const entry = &self.wash[y * width + x];
        for (0..3) |channel| entry[channel] += weight * f(color[channel]) / peak;
        entry[3] += weight;
    }
    fn applyWash(self: *Raster, strength: f32, dark: f32) void {
        if (strength == 0 and dark == 0) return;
        for (0..height) |y| for (0..width) |x| {
            const pixel_rgb = self.pixels[(y * width + x) * 4 ..][0..3];
            const light_ink = pixel_rgb[0];
            const covered = self.wash[y * width + x][3] > 0;
            if (light_ink == 0 and (!covered or dark == 0)) continue;
            const ink = if (light_ink > 0) f(light_ink) else 255 * dark;
            var sum: [4]f32 = @splat(0);
            // Smooth only chroma; leave the original dots and edges untouched.
            for (y -| 1..@min(height, y + 2)) |sy| for (x -| 1..@min(width, x + 2)) |sx| {
                for (0..4) |channel| sum[channel] += self.wash[sy * width + sx][channel];
            };
            if (sum[3] == 0) continue;
            const peak = @max(sum[0], sum[1], sum[2], 1e-8);
            for (0..3) |channel| pixel_rgb[channel] = byte(ink * (1 - strength + strength * sum[channel] / peak));
        };
    }
    pub fn render(self: *Raster, scene: Scene) void {
        if ((scene.tone == 5 or scene.tone == 6)) @memset(&self.wash, @splat(0));
        defer if ((scene.tone == 5 or scene.tone == 6)) self.applyWash(scene.wash_strength, if (scene.tone == 6) scene.dark_ink else 0);
        @memset(&self.depth, -std.math.inf(f32));
        for (0..height) |y| {
            for (0..width) |x| {
                const dx = (f(x) - width / 2) / width;
                const dy = (f(y) - height / 2) / height;
                const v = @max(0, 1 - @sqrt(dx * dx + dy * dy));
                const i = (y * width + x) * 4;
                self.pixels[i] = byte(7 + v * 5);
                self.pixels[i + 1] = byte(12 + v * 9);
                self.pixels[i + 2] = byte(22 + v * 14);
                self.pixels[i + 3] = 255;
            }
        }
        if (scene.tone >= 2) {
            for (0..width * height) |i| @memset(self.pixels[i * 4 ..][0..3], 0);
        }
        if (scene.shape == 3) {
            self.hypercube(scene);
            return;
        }
        if (scene.shape == 4) {
            self.fractal(scene);
            return;
        }
        const ca: f32 = @floatCast(@cos(scene.angle));
        const sa: f32 = @floatCast(@sin(scene.angle));
        const ct = @cos(scene.tilt);
        const st = @sin(scene.tilt);
        const nu = 36;
        const nv = 18;
        var vertices: [(nu + 1) * (nv + 1)]V = undefined;
        for (0..nu + 1) |u| {
            for (0..nv + 1) |v| {
                const a = f(u) / nu * std.math.pi * 2;
                const b = f(v) / nv * std.math.pi * 2;
                var x: f32 = undefined;
                var y: f32 = undefined;
                var z: f32 = undefined;
                if (scene.shape == 0) {
                    const r = 1 + 0.38 * @cos(b);
                    x = r * @cos(a);
                    y = r * @sin(a);
                    z = 0.38 * @sin(b);
                } else if (scene.shape == 1) {
                    const p = f(v) / nv * std.math.pi;
                    const r: f32 = @floatCast(1 + 0.13 * @sin(a * 5 + scene.angle * 2) * @sin(p * 4));
                    x = r * @sin(p) * @cos(a);
                    y = r * @cos(p);
                    z = r * @sin(p) * @sin(a);
                } else {
                    x = (f(u) / nu - 0.5) * 2.7;
                    y = (f(v) / nv - 0.5) * 2.7;
                    z = @floatCast(0.27 * @sin(x * 3 + scene.angle * 2) * @cos(y * 3 - scene.angle));
                }
                const xx = x * ca + z * sa;
                const zz = z * ca - x * sa;
                const yy = y * ct - zz * st;
                const zzz = y * st + zz * ct;
                const scale = 64 * scene.zoom / (1 - zzz / 5);
                vertices[u * (nv + 1) + v] = .{ .x = width / 2 + xx * scale, .y = height / 2 - yy * scale, .z = zzz, .wx = xx, .wy = yy, .uv = .{ f(u) / nu, f(v) / nv }, .inv_w = 1 / (1 - zzz / 5) };
            }
        }
        for (0..nu) |u| {
            for (0..nv) |v| {
                const a = u * (nv + 1) + v;
                const b = a + nv + 1;
                self.triangle(vertices[a], vertices[b], vertices[a + 1], a, scene);
                self.triangle(vertices[b], vertices[b + 1], vertices[a + 1], a, scene);
            }
        }
    }
    fn hypercube(self: *Raster, scene: Scene) void {
        var vertices: [16]V = undefined;
        for (0..16) |i| {
            var p: [4]f32 = undefined;
            for (0..4) |axis| p[axis] = if (i & (@as(usize, 1) << @intCast(axis)) == 0) -0.72 else 0.72;
            const planes = [3][2]usize{ .{ 0, 3 }, .{ 1, 2 }, .{ 2, 3 } };
            for (planes, 0..) |plane, j| {
                const angle = scene.angle * (1 + f(j) * 0.37) + scene.tilt * f(j);
                const a = p[plane[0]];
                const b = p[plane[1]];
                p[plane[0]] = @floatCast(a * @cos(angle) - b * @sin(angle));
                p[plane[1]] = @floatCast(a * @sin(angle) + b * @cos(angle));
            }
            const w = 1 / (1 - p[3] / 2.6);
            const xx = p[0] * w;
            const yy = (p[1] * @cos(scene.tilt) - p[2] * @sin(scene.tilt)) * w;
            const zz = (p[1] * @sin(scene.tilt) + p[2] * @cos(scene.tilt)) * w;
            const inv = 1 / (1 - zz / 5);
            vertices[i] = .{ .x = width / 2 + xx * 64 * scene.zoom * inv, .y = height / 2 - yy * 64 * scene.zoom * inv, .z = zz, .wx = xx, .wy = yy, .inv_w = w * inv };
        }
        // All 24 square faces, each with its own persistent local UV frame.
        for (0..4) |a| for (a + 1..4) |b| {
            const ba = @as(usize, 1) << @intCast(a);
            const bb = @as(usize, 1) << @intCast(b);
            for (0..16) |i| {
                if (i & (ba | bb) != 0) continue;
                var face = [4]V{ vertices[i], vertices[i | ba], vertices[i | bb], vertices[i | ba | bb] };
                face[0].uv = .{ 0, 0 };
                face[1].uv = .{ 1, 0 };
                face[2].uv = .{ 0, 1 };
                face[3].uv = .{ 1, 1 };
                if (scene.wire) continue;
                self.triangle(face[0], face[1], face[2], (a + b) * 180, scene);
                self.triangle(face[1], face[3], face[2], (a + b) * 180, scene);
            }
        };
        // Depth-tested edges and vertex markers make the 4D projection readable.
        for (0..16) |i| {
            var a = vertices[i];
            a.z += 0.015;
            for (0..4) |axis| {
                const other = i ^ (@as(usize, 1) << @intCast(axis));
                if (other <= i) continue;
                var b = vertices[other];
                b.z += 0.015;
                self.line(a, b, if (scene.tone >= 1) .{ 230, 230, 230 } else .{ 142, 239, 217 });
                // Faint dashed occluded edges reveal the nested 4D structure.
                const steps: usize = @intFromFloat(@ceil(@max(@abs(b.x - a.x), @abs(b.y - a.y))));
                for (0..steps + 1) |step| {
                    if (step % 5 >= 2) continue;
                    const t = if (steps == 0) 0 else f(step) / f(steps);
                    const x: i32 = @intFromFloat(@round(a.x + (b.x - a.x) * t));
                    const y: i32 = @intFromFloat(@round(a.y + (b.y - a.y) * t));
                    if (x < 0 or x >= width or y < 0 or y >= height) continue;
                    const k: usize = @intCast(y * width + x);
                    if (a.z + (b.z - a.z) * t < self.depth[k]) {
                        const color: [3]u8 = if (scene.tone >= 2) .{ 255, 255, 255 } else .{ 47, 89, 96 };
                        @memcpy(self.pixels[k * 4 ..][0..3], &color);
                    }
                }
            }
            const px: i32 = @intFromFloat(@round(a.x));
            const py: i32 = @intFromFloat(@round(a.y));
            for (0..3) |oy| for (0..3) |ox| self.pixel(px + @as(i32, @intCast(ox)) - 1, py + @as(i32, @intCast(oy)) - 1, a.z + 0.01, .{ 255, 255, 255 });
        }
    }
    fn fractal(self: *Raster, scene: Scene) void {
        const span = 3.2 / scene.fractal_zoom;
        for (0..height) |y| for (0..width) |x| {
            const cr = scene.center_x + (@as(f64, @floatFromInt(x)) / width - 0.5) * span;
            const ci = scene.center_y + (@as(f64, @floatFromInt(y)) / height - 0.5) * span * height / width;
            var zr: f64 = 0;
            var zi: f64 = 0;
            var iteration: usize = 0;
            while (iteration < 320 and zr * zr + zi * zi < 256) : (iteration += 1) {
                const nr = zr * zr - zi * zi + cr;
                zi = 2 * zr * zi + ci;
                zr = nr;
            }
            var color = [3]u8{ 0, 0, 0 };
            if (iteration < 320) {
                const smooth: f32 = @floatCast(@as(f64, @floatFromInt(iteration)) + 1 - @log2(@log2(@sqrt(zr * zr + zi * zi))));
                const phase = smooth * 0.12 + scene.angle * 0.25 + f(scene.palette) * 2.1;
                for (0..3) |channel| color[channel] = byte(@floatCast(127.5 + 127.5 * @cos(phase + f(channel) * 2.1)));
            }
            const step: f32 = @floatCast(span / width);
            const uv: dither.PreciseUV = .{ cr, ci };
            if ((scene.tone == 5 or scene.tone == 6)) self.addWash(x, y, color, 0);
            const out = toned(scene, color, @intCast(x), @intCast(y), uv, .{ step, 0 }, .{ 0, step });
            @memcpy(self.pixels[(y * width + x) * 4 ..][0..3], &out);
        };
    }
};
test "CPU geometry changes pixels and writes opaque frames" {
    var raster: Raster = undefined;
    raster.render(.{});
    const hash = std.hash.Wyhash.hash(0, &raster.pixels);
    raster.render(.{ .shape = 1, .angle = 1 });
    try std.testing.expect(hash != std.hash.Wyhash.hash(0, &raster.pixels));
    for (0..width * height) |i| try std.testing.expectEqual(@as(u8, 255), raster.pixels[i * 4 + 3]);
}

test "hypercube and fractal have distinct opaque frames and one-bit surfaces" {
    var raster: Raster = undefined;
    raster.render(.{ .shape = 3, .angle = 0.7 });
    const hash = std.hash.Wyhash.hash(0, &raster.pixels);
    raster.render(.{ .shape = 4 });
    try std.testing.expect(hash != std.hash.Wyhash.hash(0, &raster.pixels));
    const overview = std.hash.Wyhash.hash(0, &raster.pixels);
    raster.render(.{ .shape = 4, .fractal_zoom = 250, .center_x = -0.743643887037151, .center_y = 0.13182590420533 });
    try std.testing.expect(overview != std.hash.Wyhash.hash(0, &raster.pixels));
    raster.render(.{ .tone = 3, .angle = 0.5 });
    var white: usize = 0;
    for (0..width * height) |i| {
        const v = raster.pixels[i * 4];
        try std.testing.expect(v == 0 or v == 255);
        try std.testing.expectEqual(v, raster.pixels[i * 4 + 1]);
        try std.testing.expectEqual(v, raster.pixels[i * 4 + 2]);
        try std.testing.expectEqual(@as(u8, 255), raster.pixels[i * 4 + 3]);
        white += @intFromBool(v == 255);
    }
    try std.testing.expect(white > 100 and white < width * height / 2);
}

pub fn valid(scene: Scene) bool {
    if (!std.math.isFinite(scene.rotation_speed) or scene.rotation_speed < -4 or scene.rotation_speed > 4 or scene.charset > 8 or scene.cols < 1 or scene.cols > 240 or scene.rows < 1 or scene.rows > 80 or scene.fps < 1 or scene.fps > 120 or scene.shape > 4 or scene.palette > 2 or !std.math.isFinite(scene.angle) or !std.math.isFinite(scene.tilt) or !std.math.isFinite(scene.zoom) or scene.zoom < 0.3 or scene.zoom > 8) return false;
    if (scene.tone > 6 or !std.math.isFinite(scene.dark_ink) or scene.dark_ink < 0 or scene.dark_ink > 0.5 or !std.math.isFinite(scene.wash_strength) or scene.wash_strength < 0 or scene.wash_strength > 1 or !std.math.isFinite(scene.brightness) or @abs(scene.brightness) > 1 or
        !std.math.isFinite(scene.contrast) or scene.contrast < 0.25 or scene.contrast > 4 or
        !std.math.isFinite(scene.dot_scale) or scene.dot_scale < 0 or scene.dot_scale > 5 or
        !std.math.isFinite(scene.fractal_zoom) or scene.fractal_zoom < 0.5 or scene.fractal_zoom > 1e10 or
        !std.math.isFinite(scene.center_x) or @abs(scene.center_x) > 4 or
        !std.math.isFinite(scene.center_y) or @abs(scene.center_y) > 4) return false;
    return true;
}

test "high zoom scenes remain valid and render in both shading modes" {
    try std.testing.expect(valid(.{ .zoom = 8 }));
    try std.testing.expect(!valid(.{ .zoom = 8.01 }));
    var raster: Raster = undefined;
    for (0..4) |shape| {
        raster.render(.{ .shape = @intCast(shape), .zoom = 8, .angle = 0.7, .tone = 3 });
        raster.render(.{ .shape = @intCast(shape), .zoom = 8, .angle = 0.7, .wire = true });
    }
}

test "surface fractal color preserves monochrome coverage and adds face hues" {
    var mono: Raster = undefined;
    var color: Raster = undefined;
    mono.render(.{ .shape = 3, .angle = 0.7, .tone = 3, .zoom = 2 });
    color.render(.{ .shape = 3, .angle = 0.7, .tone = 4, .zoom = 2 });
    var tinted: usize = 0;
    var dark: usize = 0;
    for (0..width * height) |i| {
        const a = mono.pixels[i * 4 ..][0..3];
        const b = color.pixels[i * 4 ..][0..3];
        const lit = @max(a[0], a[1], a[2]) > 0;
        try std.testing.expectEqual(lit, @max(b[0], b[1], b[2]) > 0);
        tinted += @intFromBool(b[0] != b[1] or b[1] != b[2]);
        dark += @intFromBool(!lit);
    }
    try std.testing.expect(tinted > 100);
    try std.testing.expect(dark > 100);
}

test "color wash preserves monochrome pixels at zero and coverage at full strength" {
    var mono: Raster = undefined;
    var washed: Raster = undefined;
    const base = Scene{ .shape = 3, .angle = 0.65, .zoom = 2.5, .tone = 3 };
    mono.render(base);
    var scene = base;
    scene.tone = 5;
    scene.wash_strength = 0;
    washed.render(scene);
    try std.testing.expectEqualSlices(u8, &mono.pixels, &washed.pixels);
    scene.wash_strength = 1;
    washed.render(scene);
    var tinted: usize = 0;
    for (0..width * height) |i| {
        const rgb = washed.pixels[i * 4 ..][0..3];
        try std.testing.expectEqual(mono.pixels[i * 4], @max(rgb[0], rgb[1], rgb[2]));
        tinted += @intFromBool(rgb[0] != rgb[1] or rgb[1] != rgb[2]);
    }
    try std.testing.expect(tinted > 100);
}

test "wash color combines contributions from front and back independently of mask" {
    var raster: Raster = undefined;
    @memset(&raster.wash, @splat(0));
    @memset(&raster.pixels, 0);
    @memset(raster.pixels[0..3], 255);
    raster.addWash(0, 0, .{ 255, 0, 0 }, 1);
    raster.addWash(0, 0, .{ 0, 0, 255 }, -1);
    raster.applyWash(1, 0);
    try std.testing.expectEqual(@as(u8, 255), raster.pixels[0]);
    try std.testing.expectEqual(@as(u8, 0), raster.pixels[1]);
    try std.testing.expect(raster.pixels[2] > 100);
    try std.testing.expectEqual(@as(u8, 0), raster.pixels[4]);
}

test "two-shade ink fills only covered gaps and zero matches wash" {
    var wash: Raster = undefined;
    var shaded: Raster = undefined;
    const scene = Scene{ .shape = 3, .angle = 0.65, .tone = 5, .zoom = 0.7 };
    wash.render(scene);
    var next = scene;
    next.tone = 6;
    next.dark_ink = 0;
    shaded.render(next);
    try std.testing.expectEqualSlices(u8, &wash.pixels, &shaded.pixels);
    next.dark_ink = 0.5;
    shaded.render(next);
    var filled: usize = 0;
    var outside: usize = 0;
    for (0..width * height) |i| {
        const a = wash.pixels[i * 4 ..][0..3];
        const b = shaded.pixels[i * 4 ..][0..3];
        if (@max(a[0], a[1], a[2]) > 180) {
            try std.testing.expectEqualSlices(u8, a, b);
        } else if (shaded.wash[i][3] > 0) {
            try std.testing.expect(@max(b[0], b[1], b[2]) > 0 and @max(b[0], b[1], b[2]) < 180);
            filled += 1;
        } else {
            try std.testing.expectEqualSlices(u8, a, b);
            outside += 1;
        }
    }
    try std.testing.expect(filled > 100 and outside > 100);
}
