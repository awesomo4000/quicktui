//! Embedded-pack runtime. Deliberately contains no filesystem module loader.
const Config = @import("module_config.zig").Config;
const commonjs = @embedFile("quicktui-loader-cjs");
var config: Config = .{ .commonjs = commonjs.ptr, .commonjs_len = commonjs.len };
pub export fn qt_modules_config() *const Config {
    return &config;
}
/// The caller owns these trusted bytes for the lifetime of all UI runtimes.
pub fn enablePack(pack: []const u8) void {
    config.pack = pack.ptr;
    config.pack_len = pack.len;
    config.active = 1;
}
