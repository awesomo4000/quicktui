const std = @import("std");
const cpu = @import("lab_raster.zig");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("unistd.h");
    @cInclude("sys/stat.h");
    @cInclude("stdlib.h");
});
const allocator = std.heap.c_allocator;
pub const Preset = struct { version: u32 = 1, description: []const u8, description_auto: ?bool = null, scene: cpu.Scene, output: u32, glyph: u32 };
pub const max_slots = 128;
pub const Request = struct { start: u32 = 1, preset: enum { list, save, load }, slot: u32 = 1, value: ?Preset = null };
pub const Store = struct {
    directory: [:0]const u8 = ".quicktui-presets",
    fn path(self: Store, buf: []u8, slot: u32) ![:0]const u8 {
        if (slot < 1 or slot > max_slots) return error.InvalidSlot;
        return std.fmt.bufPrintZ(buf, "{s}/{d}.json", .{ self.directory, slot });
    }
    fn read(self: Store, slot: u32, buffer: []u8) ![]u8 {
        var pathbuf: [1024]u8 = undefined;
        const filename = try self.path(&pathbuf, slot);
        const file = c.fopen(filename, "rb") orelse return error.UnreadableSlot;
        defer _ = c.fclose(file);
        const len = c.fread(buffer.ptr, 1, buffer.len, file);
        if (c.ferror(file) != 0) return error.ReadFailed;
        if (len == buffer.len) return error.PresetTooLarge;
        return buffer[0..len];
    }
    fn validate(value: Preset) !void {
        if (value.version != 1 or value.description.len > 240 or !std.unicode.utf8ValidateSlice(value.description) or
            !cpu.valid(value.scene) or value.output > 3 or value.glyph < 1 or value.glyph > 8) return error.InvalidPreset;
        if (try std.unicode.utf8CountCodepoints(value.description) > 120) return error.InvalidDescription;
        for (value.description) |ch| if (ch < 32 or ch == 127) return error.InvalidDescription;
    }
    fn save(self: Store, slot: u32, value: Preset) !void {
        try validate(value);
        var pathbuf: [1024]u8 = undefined;
        const filename = try self.path(&pathbuf, slot);
        const data = try std.json.Stringify.valueAlloc(allocator, value, .{ .whitespace = .indent_2 });
        defer allocator.free(data);
        if (data.len >= 4096) return error.PresetTooLarge;
        _ = c.mkdir(self.directory, 0o700);
        var tmpbuf: [1024]u8 = undefined;
        const temporary = try std.fmt.bufPrintZ(&tmpbuf, "{s}/.save-XXXXXX", .{self.directory});
        const fd = c.mkstemp(temporary.ptr);
        if (fd < 0) return error.SaveFailed;
        defer _ = c.unlink(temporary);
        const file = c.fdopen(fd, "wb") orelse {
            _ = c.close(fd);
            return error.SaveFailed;
        };
        var closed = false;
        defer if (!closed) {
            _ = c.fclose(file);
        };
        if (c.fwrite(data.ptr, 1, data.len, file) != data.len or c.fflush(file) != 0 or c.fsync(fd) != 0) return error.SaveFailed;
        const result = c.fclose(file);
        closed = true;
        if (result != 0 or c.rename(temporary, filename) != 0) return error.SaveFailed;
    }
    pub fn execute(self: Store, request: Request, out: []u8) []const u8 {
        return self.perform(request, out) catch |err| std.fmt.bufPrint(out, "{{\"type\":\"presets\",\"error\":\"{s}\"}}", .{@errorName(err)}) catch unreachable;
    }
    fn perform(self: Store, request: Request, out: []u8) ![]const u8 {
        if (request.preset == .save) {
            try self.save(request.slot, request.value orelse return error.MissingPreset);
            return try std.fmt.bufPrint(out, "{{\"type\":\"presets\",\"saved\":{d}}}", .{request.slot});
        }
        if (request.preset == .load) {
            var buffer: [4096]u8 = undefined;
            const data = try self.read(request.slot, &buffer);
            const parsed = try std.json.parseFromSlice(Preset, allocator, data, .{});
            defer parsed.deinit();
            try validate(parsed.value);
            const response = try std.json.Stringify.valueAlloc(allocator, .{ .type = "presets", .slot = request.slot, .value = parsed.value }, .{});
            defer allocator.free(response);
            if (response.len > out.len) return error.ResponseTooLarge;
            @memcpy(out[0..response.len], response);
            return out[0..response.len];
        }
        const Entry = struct { slot: usize, description: []const u8, description_auto: ?bool = null };
        if (request.start < 1 or request.start > max_slots) return error.InvalidSlot;
        const count = @min(4, max_slots + 1 - request.start);
        var entries: [4]Entry = undefined;
        var descriptions: [4][240]u8 = undefined;
        for (0..count) |i| {
            entries[i] = .{ .slot = request.start + i, .description = "" };
            var buffer: [4096]u8 = undefined;
            const data = self.read(@intCast(request.start + i), &buffer) catch continue;
            const parsed = std.json.parseFromSlice(Preset, allocator, data, .{}) catch {
                entries[i].description = "[invalid preset]";
                continue;
            };
            defer parsed.deinit();
            validate(parsed.value) catch {
                entries[i].description = "[invalid preset]";
                continue;
            };
            entries[i].description_auto = parsed.value.description_auto;
            const description = parsed.value.description;
            @memcpy(descriptions[i][0..description.len], description);
            entries[i].description = descriptions[i][0..description.len];
        }
        const response = try std.json.Stringify.valueAlloc(allocator, .{ .type = "presets", .slots = entries[0..count], .next = if (request.start + count <= max_slots) @as(?u32, request.start + count) else null, .total = max_slots }, .{});
        defer allocator.free(response);
        if (response.len > out.len) return error.ResponseTooLarge;
        @memcpy(out[0..response.len], response);
        return out[0..response.len];
    }
};
test "presets survive a new store and invalid saves preserve the previous slot" {
    var directory = "/tmp/quicktui-presets-XXXXXX".*;
    const dir = c.mkdtemp(&directory) orelse return error.TempFailed;
    const store = Store{ .directory = std.mem.span(dir) };
    defer {
        var buf: [1024]u8 = undefined;
        const path = store.path(&buf, 1) catch unreachable;
        _ = c.unlink(path);
        _ = c.rmdir(dir);
    }
    const value = Preset{ .description = "Emerald braille", .description_auto = true, .scene = .{ .shape = 4, .tone = 6, .wash_strength = 0.65, .dark_ink = 0.25, .fps = 90, .rotation_speed = -0.125, .zoom = 8, .angle = 1.75 }, .output = 3, .glyph = 8 };
    try store.save(1, value);
    var out: [4096]u8 = undefined;
    const fresh = Store{ .directory = store.directory };
    const response = fresh.execute(.{ .preset = .load, .slot = 1 }, &out);
    try std.testing.expect(std.mem.find(u8, response, "Emerald braille") != null);
    try std.testing.expect(std.mem.find(u8, response, "\"rotation_speed\":-0.125") != null);
    try std.testing.expect(std.mem.find(u8, response, "\"description_auto\":true") != null);
    var bad = value;
    bad.scene.fps = 121;
    try std.testing.expectError(error.InvalidPreset, store.save(1, bad));
    const response2 = fresh.execute(.{ .preset = .load, .slot = 1 }, &out);
    try std.testing.expect(std.mem.find(u8, response2, "\"fps\":90") != null);
}

pub const Temporary = struct {
    buffer: [64:0]u8 = undefined,
    directory: [:0]const u8 = "",
    pub fn init(self: *Temporary) !void {
        const template = try std.fmt.bufPrintZ(&self.buffer, "/tmp/quicktui-presets-XXXXXX", .{});
        const dir = c.mkdtemp(template.ptr) orelse return error.TempFailed;
        self.directory = std.mem.span(dir);
    }
    pub fn deinit(self: *Temporary) void {
        const store = Store{ .directory = self.directory };
        for (1..max_slots + 1) |slot| {
            var buffer: [1024]u8 = undefined;
            const filename = store.path(&buffer, @intCast(slot)) catch continue;
            _ = c.unlink(filename);
        }
        _ = c.rmdir(self.directory);
    }
};

test "128 slots paginate within the message limit even with escaped descriptions" {
    var temporary: Temporary = .{};
    try temporary.init();
    defer temporary.deinit();
    const store = Store{ .directory = temporary.directory };
    const value = Preset{ .description = &(@as([120]u8, @splat('"'))), .scene = .{}, .output = 0, .glyph = 1 };
    for (1..max_slots + 1) |slot| try store.save(@intCast(slot), value);
    try std.testing.expectError(error.InvalidSlot, store.save(0, value));
    try std.testing.expectError(error.InvalidSlot, store.save(129, value));
    var out: [4096]u8 = undefined;
    var start: u32 = 1;
    var seen: usize = 0;
    while (true) {
        const response = store.execute(.{ .preset = .list, .start = start }, &out);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
        defer parsed.deinit();
        const slots = parsed.value.object.get("slots").?.array.items;
        for (slots) |entry| {
            seen += 1;
            try std.testing.expectEqual(@as(i64, @intCast(seen)), entry.object.get("slot").?.integer);
            try std.testing.expectEqualStrings(value.description, entry.object.get("description").?.string);
        }
        const next = parsed.value.object.get("next").?;
        if (next == .null) break;
        start = @intCast(next.integer);
    }
    try std.testing.expectEqual(128, seen);
    try std.testing.expect(std.mem.find(u8, store.execute(.{ .preset = .load, .slot = 128 }, &out), "\"value\":") != null);
}
