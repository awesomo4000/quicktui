const qt = @import("quicktui");
pub fn main() !void {
    try qt.runPack(@embedFile("app.pack"), .{ .reload = true });
}
