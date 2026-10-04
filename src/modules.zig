//! OS layer for source-module mode: file reads, the bytecode cache, hashing,
//! and the loader configuration consumed by src/module_loader.c.
//!
//! Source mode loads `.ts`/`.tsx` modules straight from a checkout instead of
//! the prebuilt bundle. Sucrase (vendor/sucrase) strips types and converts JSX
//! inside QuickJS; compiled modules are cached as QuickJS bytecode keyed by a
//! BLAKE3 hash of the loader, the transform, and the module source.
//!
//! A module pack is the same bytecode plus the resolution table, written once
//! by `buildPack` and loaded by `enablePack`, usually from @embedFile. An
//! pack needs no checkout, no Sucrase run, and no cache.
const std = @import("std");
const c = std.c;

const sucrase_source = @embedFile("quicktui-sucrase");
const policy_source = @embedFile("quicktui-loader-policy");
const commonjs_source = @embedFile("quicktui-loader-cjs");
/// Checkout this binary was built from; js/ and vendor/ are loaded from here.
pub const default_root: [:0]const u8 = @import("quicktui_build_options").source_root ++ "";

/// Read by module_loader.c. Strings are NUL-terminated and live for the process.
pub const Config = @import("module_config.zig").Config;

var config: Config = .{
    .sucrase = sucrase_source.ptr,
    .sucrase_len = sucrase_source.len,
    .policy = policy_source.ptr,
    .policy_len = policy_source.len,
    .commonjs = commonjs_source.ptr,
    .commonjs_len = commonjs_source.len,
};

pub export fn qt_modules_config() *const Config {
    return &config;
}

pub const Options = struct {
    /// Checkout root containing js/ and vendor/.
    root: [:0]const u8,
    /// Entry module, absolute or relative to root.
    entry: [:0]const u8,
    demo_assets: bool = false,
    /// Application source tree; defaults to the entry directory.
    app_root: ?[:0]const u8 = null,
    /// Overrides the default cache directory; empty disables the cache.
    cache_dir: ?[:0]const u8 = null,
    /// buildPack only: depfile path for build systems.
    depfile: [:0]const u8 = "",
    /// buildPack only: no summary on stderr.
    quiet: bool = false,
};

/// Switch the next application runs to source-module mode.
pub fn enable(allocator: std.mem.Allocator, options: Options) !void {
    const root = try absolute(allocator, options.root);
    config.root = root;
    config.entry = if (options.entry.len > 0 and options.entry[0] == '/') options.entry else try std.fmt.allocPrintSentinel(allocator, "{s}/{s}", .{ root, options.entry }, 0);
    config.app_root = if (options.app_root) |path| try absolute(allocator, path) else "";
    config.demo_assets = @intFromBool(options.demo_assets);
    config.cache_dir = if (options.cache_dir) |dir| dir else try defaultCacheDir(allocator);
    config.trace = @intFromBool(getenv("QUICKTUI_TRACE_MODULES") != null);
    config.active = 1;
}

/// Load modules from a prebuilt pack. Combine with `enable` to fall back to
/// a checkout for modules the pack lacks (an application under development).
pub fn enablePack(pack: []const u8) void {
    config.pack = pack.ptr;
    config.pack_len = pack.len;
    config.trace = @intFromBool(getenv("QUICKTUI_TRACE_MODULES") != null);
    config.active = 1;
}

/// Read a pack file for the rest of the process (bytecode references it).
pub fn readPack(path: [:0]const u8) ![]const u8 {
    var len: usize = 0;
    const bytes = qt_fs_read(path.ptr, &len) orelse return error.FileNotFound;
    return bytes[0..len];
}

extern "c" fn quicktui_build_pack(out_path: [*:0]const u8) c_int;

/// Compile every module reachable from `options.entry` (static imports plus
/// literal require() targets) and write a module pack to `out_path`.
/// The ES entry is not evaluated; CommonJS export discovery can execute dependencies.
pub fn buildPack(allocator: std.mem.Allocator, options: Options, out_path: [:0]const u8) !void {
    try enable(allocator, options);
    config.depfile = options.depfile;
    config.quiet = @intFromBool(options.quiet);
    config.record = 1;
    defer config.record = 0;
    if (quicktui_build_pack(out_path.ptr) != 0) return error.PackBuildFailed;
}

fn getenv(name: [*:0]const u8) ?[:0]const u8 {
    const value = c.getenv(name) orelse return null;
    return std.mem.span(value);
}

extern "c" fn realpath(path: [*:0]const u8, resolved: ?[*]u8) ?[*:0]u8;
extern "c" fn close(fd: c.fd_t) c_int;

pub fn absolute(allocator: std.mem.Allocator, path: [:0]const u8) ![:0]const u8 {
    const resolved = realpath(path, null) orelse return error.FileNotFound;
    defer c.free(resolved);
    return allocator.dupeZ(u8, std.mem.span(resolved));
}

fn defaultCacheDir(allocator: std.mem.Allocator) ![:0]const u8 {
    if (getenv("QUICKTUI_CACHE")) |dir| return dir;
    if (getenv("XDG_CACHE_HOME")) |dir| if (dir.len > 0) return std.fmt.allocPrintSentinel(allocator, "{s}/quicktui/modules", .{dir}, 0);
    if (getenv("HOME")) |home| return std.fmt.allocPrintSentinel(allocator, "{s}/.cache/quicktui/modules", .{home}, 0);
    return "";
}

// ---- Files ------------------------------------------------------------------

/// Whole-file read into malloc storage (freed with qt_free). NULL if unreadable.
pub export fn qt_fs_read(path: [*:0]const u8, out_len: *usize) ?[*]u8 {
    const fd = c.open(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true });
    if (fd < 0) return null;
    defer _ = close(fd);
    var capacity: usize = 64 * 1024;
    var buffer: [*]u8 = @ptrCast(c.malloc(capacity) orelse return null);
    var len: usize = 0;
    while (true) {
        if (len == capacity) {
            capacity *= 2;
            buffer = @ptrCast(c.realloc(buffer, capacity) orelse {
                c.free(buffer);
                return null;
            });
        }
        const n = c.read(fd, buffer + len, capacity - len);
        if (n < 0) {
            if (std.posix.errno(n) == .INTR) continue;
            c.free(buffer);
            return null;
        }
        if (n == 0) break;
        len += @intCast(n);
    }
    out_len.* = len;
    return buffer;
}

/// Openable and not a directory. (std.c has no portable stat on Linux in 0.16.)
/// Write a whole file atomically (temporary file, then rename). 0 on success.
pub export fn qt_fs_write(path: [*:0]const u8, bytes: [*]const u8, len: usize) c_int {
    var temp_buffer: [4096]u8 = undefined;
    const temp = std.fmt.bufPrintSentinel(&temp_buffer, "{s}.{d}.tmp", .{ std.mem.span(path), c.getpid() }, 0) catch return -1;
    const fd = c.open(temp, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, @as(c.mode_t, 0o644));
    if (fd < 0) return -1;
    const ok = writeAll(fd, bytes[0..len]);
    _ = close(fd);
    if (!ok or c.rename(temp, path) != 0) {
        _ = c.unlink(temp);
        return -1;
    }
    return 0;
}

pub export fn qt_fs_is_file(path: [*:0]const u8) c_int {
    const fd = c.open(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true });
    if (fd < 0) return 0;
    _ = close(fd);
    const dir = c.open(path, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true });
    if (dir < 0) return 1;
    _ = close(dir);
    return 0;
}

pub export fn qt_free(pointer: ?*anyopaque) void {
    c.free(pointer);
}

// ---- Hashing ----------------------------------------------------------------

pub const Hash = [32]u8;

pub export fn qt_hash_new() ?*std.crypto.hash.Blake3 {
    const state: *std.crypto.hash.Blake3 = @ptrCast(@alignCast(c.malloc(@sizeOf(std.crypto.hash.Blake3)) orelse return null));
    state.* = .init(.{});
    return state;
}

/// Length-prefixed so ("ab","c") and ("a","bc") hash differently.
pub export fn qt_hash_update(state: *std.crypto.hash.Blake3, bytes: [*]const u8, len: usize) void {
    var prefix: [8]u8 = undefined;
    std.mem.writeInt(u64, &prefix, len, .little);
    state.update(&prefix);
    state.update(bytes[0..len]);
}

pub export fn qt_hash_final(state: *std.crypto.hash.Blake3, out: *Hash) void {
    state.final(out);
    c.free(state);
}

// ---- Bytecode cache -----------------------------------------------------------
//
// <cache_dir>/<key-hex>.qbc = magic(8) ++ blake3(payload)(32) ++ payload.
// The payload digest rejects truncated or corrupted entries before QuickJS
// parses them. QuickJS bytecode is not a safe format for untrusted input; the
// cache directory must be writable only by the user running QuickTUI.

const magic = "QTBC\x00\x00\x00\x01";

fn entryPath(buffer: []u8, key: *const Hash, suffix: []const u8) ?[:0]const u8 {
    const dir = std.mem.span(config.cache_dir);
    if (dir.len == 0) return null;
    const hex = std.fmt.bytesToHex(key.*, .lower);
    return std.fmt.bufPrintSentinel(buffer, "{s}/{s}{s}", .{ dir, hex, suffix }, 0) catch null;
}

/// Returns the cached payload in malloc storage (freed with qt_free), or NULL.
pub export fn qt_cache_get(key: *const Hash, out_len: *usize) ?[*]u8 {
    var path_buffer: [4096]u8 = undefined;
    const path = entryPath(&path_buffer, key, ".qbc") orelse return null;
    var len: usize = 0;
    const bytes = qt_fs_read(path, &len) orelse return null;
    const header = magic.len + 32;
    if (len < header or !std.mem.eql(u8, bytes[0..magic.len], magic)) {
        c.free(bytes);
        return null;
    }
    var digest: Hash = undefined;
    std.crypto.hash.Blake3.hash(bytes[header..len], &digest, .{});
    if (!std.mem.eql(u8, &digest, bytes[magic.len..header])) {
        c.free(bytes);
        return null;
    }
    std.mem.copyForwards(u8, bytes[0 .. len - header], bytes[header..len]);
    out_len.* = len - header;
    return bytes;
}

/// Best effort: failures leave the cache unchanged.
pub export fn qt_cache_put(key: *const Hash, payload: [*]const u8, len: usize) void {
    var path_buffer: [4096]u8 = undefined;
    var temp_buffer: [4096]u8 = undefined;
    const path = entryPath(&path_buffer, key, ".qbc") orelse return;
    var suffix_buffer: [32]u8 = undefined;
    const suffix = std.fmt.bufPrint(&suffix_buffer, ".{d}.tmp", .{c.getpid()}) catch return;
    const temp = entryPath(&temp_buffer, key, suffix) orelse return;
    makeDirs(std.mem.span(config.cache_dir));
    const fd = c.open(temp, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, @as(c.mode_t, 0o600));
    if (fd < 0) return;
    var digest: Hash = undefined;
    std.crypto.hash.Blake3.hash(payload[0..len], &digest, .{});
    const ok = writeAll(fd, magic) and writeAll(fd, &digest) and writeAll(fd, payload[0..len]);
    _ = close(fd);
    if (!ok or c.rename(temp, path) != 0) _ = c.unlink(temp);
}

fn writeAll(fd: c.fd_t, bytes: []const u8) bool {
    var rest = bytes;
    while (rest.len > 0) {
        const n = c.write(fd, rest.ptr, rest.len);
        if (n < 0) {
            if (std.posix.errno(n) == .INTR) continue;
            return false;
        }
        rest = rest[@intCast(n)..];
    }
    return true;
}

fn makeDirs(path: []const u8) void {
    var buffer: [4096:0]u8 = undefined;
    if (path.len >= buffer.len) return;
    var i: usize = 1;
    while (i <= path.len) : (i += 1) {
        if (i == path.len or path[i] == '/') {
            @memcpy(buffer[0..i], path[0..i]);
            buffer[i] = 0;
            _ = c.mkdir(&buffer, 0o700);
        }
    }
}

test "cache entries round-trip and reject corruption" {
    var dir_buffer: [64]u8 = undefined;
    const dir = try std.fmt.bufPrintSentinel(&dir_buffer, "/tmp/quicktui-cache-test-{d}", .{c.getpid()}, 0);
    config.cache_dir = dir;
    defer config.cache_dir = "";
    var key: Hash = @splat(7);
    qt_cache_put(&key, "bytecode", 8);
    var len: usize = 0;
    const got = qt_cache_get(&key, &len) orelse return error.CacheMiss;
    defer qt_free(got);
    try std.testing.expectEqualStrings("bytecode", got[0..len]);

    var path_buffer: [4096]u8 = undefined;
    const path = entryPath(&path_buffer, &key, ".qbc").?;
    const fd = c.open(path, .{ .ACCMODE = .WRONLY, .APPEND = true });
    try std.testing.expect(fd >= 0);
    _ = c.write(fd, "x", 1);
    _ = close(fd);
    try std.testing.expect(qt_cache_get(&key, &len) == null);
    _ = c.unlink(path);
    _ = c.rmdir(dir);
}
