const std = @import("std");
const dither = @import("dither3d.zig");
pub const width = 240;
pub const height = 160;
pub const byte_count = width * height * 4;
pub const Scene = struct { shape: u32 = 0, angle: f32 = 0, tilt: f32 = 0.7, zoom: f32 = 0.82, wire: bool = false, palette: u32 = 0, playing: bool = true, fps: u32 = 10, charset: u32 = 0, cols: u32 = 60, rows: u32 = 20, tone: u32 = 0, brightness: f32 = 0, contrast: f32 = 1, dot_scale: f32 = 4, fractal_zoom: f64 = 1, center_x: f64 = -0.65, center_y: f64 = 0 };
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
        if (scene.tone == 3) return @splat(dither.shade(uv, dx, dy, light, scene.dot_scale));
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
                    self.pixel(x, y, w1 * a.z + w2 * b.z + w3 * c.z, toned(scene, color, x, y, uv, dx, dy));
                }
            }
        }
    }
    pub fn render(self: *Raster, scene: Scene) void {
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
        const ca = @cos(scene.angle);
        const sa = @sin(scene.angle);
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
                    const r = 1 + 0.13 * @sin(a * 5 + scene.angle * 2) * @sin(p * 4);
                    x = r * @sin(p) * @cos(a);
                    y = r * @cos(p);
                    z = r * @sin(p) * @sin(a);
                } else {
                    x = (f(u) / nu - 0.5) * 2.7;
                    y = (f(v) / nv - 0.5) * 2.7;
                    z = 0.27 * @sin(x * 3 + scene.angle * 2) * @cos(y * 3 - scene.angle);
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
                p[plane[0]] = a * @cos(angle) - b * @sin(angle);
                p[plane[1]] = a * @sin(angle) + b * @cos(angle);
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
                for (0..3) |channel| color[channel] = byte(127.5 + 127.5 * @cos(phase + f(channel) * 2.1));
            }
            const step: f32 = @floatCast(span / width);
            const uv: dither.PreciseUV = .{ cr, ci };
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
