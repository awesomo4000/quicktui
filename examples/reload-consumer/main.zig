const qt = @import("quicktui");
pub fn main() !void {
    try qt.runApp(@embedFile("app.js"), .{ .reload = true });
}
