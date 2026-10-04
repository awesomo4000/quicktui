const qt = @import("quicktui");
pub fn main() !void {
    try qt.runPack(@embedFile("input-tests.pack"), .{ .headless = true });
}
