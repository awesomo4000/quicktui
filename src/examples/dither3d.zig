// Copyright (c) 2025 Rune Skovbo Johansen
// CPU adaptation for QuickTUI.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. See vendor/dither3d/LICENSE.md or https://mozilla.org/MPL/2.0/.
const std = @import("std");
const pattern = @embedFile("dither3d/pattern.r8");
const ramp = @embedFile("dither3d/ramp.r8");
pub const UV = @Vector(2, f32);
pub const PreciseUV = @Vector(2, f64);
fn mix(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}
fn texel(x: i32, y: i32, z: i32) f32 {
    const i: usize = @intCast(@mod(x, 64) + @mod(y, 64) * 64 + @mod(z, 16) * 4096);
    return @as(f32, @floatFromInt(pattern[i])) / 255;
}
fn sample(uv: UV, layer: f32) f32 {
    const x = (uv[0] - @floor(uv[0])) * 64 - 0.5;
    const y = (uv[1] - @floor(uv[1])) * 64 - 0.5;
    const z = layer - 1;
    const ix: i32 = @intFromFloat(@floor(x));
    const iy: i32 = @intFromFloat(@floor(y));
    const iz: i32 = @intFromFloat(@floor(z));
    const fx = x - @floor(x);
    const fy = y - @floor(y);
    const fz = z - @floor(z);
    return mix(mix(mix(texel(ix, iy, iz), texel(ix + 1, iy, iz), fx), mix(texel(ix, iy + 1, iz), texel(ix + 1, iy + 1, iz), fx), fy), mix(mix(texel(ix, iy, iz + 1), texel(ix + 1, iy, iz + 1), fx), mix(texel(ix, iy + 1, iz + 1), texel(ix + 1, iy + 1, iz + 1), fx), fy), fz);
}
pub fn shade(uv: PreciseUV, dx: UV, dy: UV, brightness: f32, dot_scale: f32) u8 {
    if (brightness <= 0) return 0;
    if (brightness >= 1) return 255;
    const rpos = brightness * 63;
    const ri: usize = @intFromFloat(rpos);
    const curve = mix(@floatFromInt(ramp[ri]), @floatFromInt(ramp[@min(63, ri + 1)]), rpos - @floor(rpos)) / 255;
    const q = @reduce(.Add, dx * dx + dy * dy);
    const r = dx[0] * dy[1] - dx[1] * dy[0];
    const disc = @sqrt(@max(0, q * q - 4 * r * r));
    // r / maximum singular value avoids cancellation at grazing angles.
    const maximum = @sqrt(@max(1e-38, (q + disc) * 0.5));
    const minimum = @max(1e-20, @abs(r) / maximum);
    const spacing = minimum * @exp2(dot_scale) * 0.5 / (curve * 2 + 0.001);
    const level = @floor(@log2(spacing));
    const fraction = @log2(spacing) - level;
    const scaled = uv / @as(PreciseUV, @splat(@exp2(@as(f64, level))));
    const uv_scaled: UV = @floatCast(scaled - @floor(scaled));
    const value = sample(uv_scaled, mix(4, 16, 1 - fraction));
    // Hard 1-bit mode, equivalent to thresholding the high-contrast shader.
    return if (value >= 1 - curve) 255 else 0;
}
test "fractal texture repeats and shades endpoint brightness" {
    try std.testing.expectApproxEqAbs(sample(.{ 0.12, 0.34 }, 7.5), sample(.{ 1.12, 0.34 }, 7.5), 0.00001);
    try std.testing.expectEqual(@as(u8, 0), shade(.{ 0, 0 }, .{ 0.01, 0 }, .{ 0, 0.01 }, 0, 2));
    try std.testing.expectEqual(@as(u8, 255), shade(.{ 0, 0 }, .{ 0.01, 0 }, .{ 0, 0.01 }, 1, 2));
}
