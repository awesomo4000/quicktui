// Shared C/Zig module configuration ABI.
pub const Config = extern struct {
    active: c_int = 0,
    root: [*:0]const u8 = "",
    entry: [*:0]const u8 = "",
    demo_assets: c_int = 0,
    hosted: c_int = 1,
    sucrase: [*]const u8 = "".ptr,
    sucrase_len: usize = 0,
    policy: [*]const u8 = "".ptr,
    policy_len: usize = 0,
    commonjs: [*]const u8 = "".ptr,
    commonjs_len: usize = 0,
    /// Cache directory, or empty to disable caching.
    cache_dir: [*:0]const u8 = "",
    /// Print cache hits/misses and load timing to stderr.
    trace: c_int = 0,
    /// Module pack; must outlive every runtime (embedded or process-lifetime).
    pack: ?[*]const u8 = null,
    pack_len: usize = 0,
    /// Set while buildPack runs.
    record: c_int = 0,
    /// buildPack: write a Makefile depfile listing every file read, or "".
    depfile: [*:0]const u8 = "",
    /// buildPack: suppress the summary line.
    quiet: c_int = 0,
    app_root: [*:0]const u8 = "",
};
