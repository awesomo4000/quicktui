const std = @import("std");
const cpu = @import("lab_raster.zig");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("unistd.h");
    @cInclude("sys/stat.h");
    @cInclude("stdlib.h");
});
const allocator = std.heap.c_allocator;
pub const Preset = struct { version: u32 = 1, description: []const u8, scene: cpu.Scene, output: u32, glyph: u32 };
pub const Request = struct { preset: enum { list, save, load }, slot: u32 = 1, value: ?Preset = null };
pub const Store = struct {
    directory: [:0]const u8 = ".quicktui-presets",
    fn path(self: Store, buf: []u8, slot: u32) ![:0]const u8 {
        if (slot < 1 or slot > 9) return error.InvalidSlot;
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
        if (try std.unicode.utf8CountCodepoints(value.description) > 60) return error.InvalidDescription;
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
        const Entry = struct { slot: usize, description: []const u8 };
        var entries: [9]Entry = undefined;
        var descriptions: [9][240]u8 = undefined;
        for (0..9) |i| {
            entries[i] = .{ .slot = i + 1, .description = "" };
            var buffer: [4096]u8 = undefined;
            const data = self.read(@intCast(i + 1), &buffer) catch continue;
            const parsed = std.json.parseFromSlice(Preset, allocator, data, .{}) catch {
                entries[i].description = "[invalid preset]";
                continue;
            };
            defer parsed.deinit();
            validate(parsed.value) catch {
                entries[i].description = "[invalid preset]";
                continue;
            };
            const description = parsed.value.description;
            @memcpy(descriptions[i][0..description.len], description);
            entries[i].description = descriptions[i][0..description.len];
        }
        const response = try std.json.Stringify.valueAlloc(allocator, .{ .type = "presets", .slots = entries }, .{});
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
    const value = Preset{ .description = "Emerald braille", .scene = .{ .shape = 4, .tone = 3, .fps = 90, .rotation_speed = -0.125, .zoom = 8, .angle = 1.75 }, .output = 3, .glyph = 8 };
    try store.save(1, value);
    var out: [4096]u8 = undefined;
    const fresh = Store{ .directory = store.directory };
    const response = fresh.execute(.{ .preset = .load, .slot = 1 }, &out);
    try std.testing.expect(std.mem.find(u8, response, "Emerald braille") != null);
    try std.testing.expect(std.mem.find(u8, response, "\"rotation_speed\":-0.125") != null);
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
        for (1..10) |slot| {
            var buffer: [1024]u8 = undefined;
            const filename = store.path(&buffer, @intCast(slot)) catch continue;
            _ = c.unlink(filename);
        }
        _ = c.rmdir(self.directory);
    }
};
