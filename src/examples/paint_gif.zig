const std = @import("std");
const a = std.heap.c_allocator;
const Bytes = std.ArrayList(u8);
const Cycle = struct { start: usize, end: usize, stepMs: u32, direction: i32, blend: bool = false };
const Painting = struct { format: []const u8, version: u8, width: usize, height: usize, pixels: []const u8, palette: []const []const u8, cycle: Cycle };
fn put(out: *Bytes, data: []const u8) !void {
    try out.appendSlice(a, data);
}
fn byte(out: *Bytes, value: u8) !void {
    try out.append(a, value);
}
fn word(out: *Bytes, value: usize) !void {
    try put(out, &.{ @truncate(value), @truncate(value >> 8) });
}
const Bits = struct {
    out: Bytes = .empty,
    pending: u32 = 0,
    count: u5 = 0,
    fn emit(self: *Bits, code: u16, size: u5) !void {
        self.pending |= @as(u32, code) << self.count;
        self.count += size;
        while (self.count >= 8) {
            try byte(&self.out, @truncate(self.pending));
            self.pending >>= 8;
            self.count -= 8;
        }
    }
};
// GIF LZW. The encoder dictionary leads the decoder by one entry.
fn compress(pixels: []const u8) ![]u8 {
    var bits: Bits = .{};
    errdefer bits.out.deinit(a);
    var dict: std.AutoHashMap(u32, u16) = .init(a);
    defer dict.deinit();
    var size: u5 = 9;
    var next: u16 = 258;
    try bits.emit(256, size);
    var prefix: u16 = pixels[0];
    for (pixels[1..]) |p| {
        const key = (@as(u32, prefix) << 8) | p;
        if (dict.get(key)) |code| {
            prefix = code;
            continue;
        }
        try bits.emit(prefix, size);
        if (next < 4096) {
            try dict.put(key, next);
            next += 1;
            if (size < 12 and next > (@as(u16, 1) << @as(u4, @intCast(size)))) size += 1;
        } else {
            try bits.emit(256, size);
            dict.clearRetainingCapacity();
            size = 9;
            next = 258;
        }
        prefix = p;
    }
    try bits.emit(prefix, size);
    // Decoder installs its final entry when reading the last prefix.
    if (size < 12 and next == (@as(u16, 1) << @as(u4, @intCast(size)))) size += 1;
    try bits.emit(257, size);
    if (bits.count > 0) try byte(&bits.out, @truncate(bits.pending));
    return bits.out.toOwnedSlice(a);
}
pub fn encode(text: []const u8, width: usize) ![]u8 {
    if (width != 480 and width != 960 and width != 1440) return error.InvalidExportSize;
    const parsed = try std.json.parseFromSlice(Painting, a, text, .{});
    defer parsed.deinit();
    const p = parsed.value;
    const c = p.cycle;
    if (!std.mem.eql(u8, p.format, "termpaint") or p.version != 3 or p.width < 16 or p.width > 256 or p.height < 16 or p.height > 192 or p.pixels.len != p.width * p.height or p.palette.len != 32) return error.InvalidPainting;
    if (c.start >= c.end or c.end >= 32 or c.stepMs < 40 or c.stepMs > 2000 or (c.direction != 1 and c.direction != -1)) return error.InvalidCycle;
    const height = (width * p.height + p.width / 2) / p.width;
    if (height > 4096) return error.ExportTooTall;
    var palette: [256][3]u8 = @splat(.{ 0, 0, 0 });
    for (p.palette, 0..) |hex, i| {
        if (hex.len != 7 or hex[0] != '#') return error.InvalidPalette;
        for (0..3) |ch| palette[i][ch] = try std.fmt.parseInt(u8, hex[1 + ch * 2 .. 3 + ch * 2], 16);
    }
    const alphabet = "0123456789abcdefghijklmnopqrstuv.";
    for (p.pixels) |ch| {
        if (std.mem.indexOfScalar(u8, alphabet, ch) == null) return error.InvalidPixel;
    }
    const scaled = try a.alloc(u8, width * height);
    defer a.free(scaled);
    for (0..height) |y| for (0..width) |x| {
        scaled[y * width + x] = @intCast(std.mem.indexOfScalar(u8, alphabet, p.pixels[(y * p.height / height) * p.width + x * p.width / width]).?);
    };
    const compressed = try compress(scaled);
    defer a.free(compressed);
    const n = c.end - c.start + 1;
    const period_cs = n * c.stepMs / 10;
    const frames = if (c.blend) @min(256, @max(n, period_cs / 4)) else n;
    if (compressed.len * frames > 64 * 1024 * 1024) return error.ExportTooLarge;
    var out: Bytes = .empty;
    errdefer out.deinit(a);
    try put(&out, "GIF89a");
    try word(&out, width);
    try word(&out, height);
    try put(&out, &.{ 0xf7, 32, 0 });
    try put(&out, std.mem.asBytes(&palette));
    try put(&out, "\x21\xff\x0bNETSCAPE2.0\x03\x01\x00\x00\x00");
    for (0..frames) |frame| {
        const now = frame * period_cs / frames;
        const delay = (frame + 1) * period_cs / frames - now;
        try put(&out, &.{ 0x21, 0xf9, 4, 9 });
        try word(&out, delay);
        try put(&out, &.{ 32, 0 });
        try byte(&out, 0x2c);
        try word(&out, 0);
        try word(&out, 0);
        try word(&out, width);
        try word(&out, height);
        try byte(&out, 0x87);
        var local = palette;
        const phase = @as(f64, @floatFromInt(frame * n)) / @as(f64, @floatFromInt(frames)) * @as(f64, @floatFromInt(c.direction));
        const step: i64 = @intFromFloat(@floor(phase));
        const fraction = if (c.blend) phase - @floor(phase) else 0;
        for (0..n) |i| {
            const at: usize = @intCast(@mod(@as(i64, @intCast(i)) - step, @as(i64, @intCast(n))));
            const next = (at + n - 1) % n;
            for (0..3) |ch| local[c.start + i][ch] = @intFromFloat(@round(@as(f64, @floatFromInt(palette[c.start + at][ch])) * (1 - fraction) + @as(f64, @floatFromInt(palette[c.start + next][ch])) * fraction));
        }
        try put(&out, std.mem.asBytes(&local));
        try byte(&out, 8);
        var at: usize = 0;
        while (at < compressed.len) {
            const len = @min(255, compressed.len - at);
            try byte(&out, @intCast(len));
            try put(&out, compressed[at..][0..len]);
            at += len;
        }
        try byte(&out, 0);
    }
    try byte(&out, 0x3b);
    return out.toOwnedSlice(a);
}
