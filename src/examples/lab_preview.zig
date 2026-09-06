// CPU-only contact sheet for checking the lab without a terminal emulator.
// zig run src/examples/lab_preview.zig -lc -O ReleaseFast > /tmp/quicktui-lab.ppm
const cpu = @import("lab_raster.zig");
const c = @cImport({
    @cInclude("stdio.h");
});
pub fn main() void {
    const output = c.fdopen(1, "w");
    const scenes = [6]cpu.Scene{
        .{ .shape = 3, .angle = 0.65, .zoom = 0.7 },
        .{ .shape = 3, .angle = 0.65, .zoom = 0.7, .tone = 3 },
        .{ .shape = 3, .angle = 0.65, .zoom = 0.7, .tone = 6 },
        .{ .shape = 3, .angle = 0.65, .zoom = 2.5, .tone = 3 },
        .{ .shape = 3, .angle = 0.65, .zoom = 2.5, .tone = 6, .dark_ink = 0.25 },
        .{ .shape = 3, .angle = 0.65, .zoom = 2.5, .tone = 5 },
    };
    var rasters: [6]cpu.Raster = undefined;
    for (scenes, 0..) |scene, i| rasters[i].render(scene);
    _ = c.fprintf(output, "P6\n720 320\n255\n");
    for (0..320) |y| for (0..720) |x| {
        const tile = (y / 160) * 3 + x / 240;
        const i = ((y % 160) * 240 + x % 240) * 4;
        _ = c.fwrite(&rasters[tile].pixels[i], 1, 3, output);
    };
}
