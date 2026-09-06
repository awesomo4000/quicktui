// Adapted from the user-owned Phosphor examples/ascii-cube.zig.
// The ASCII vectors were measured from Fira Code. Other terminal fonts may differ.
const std = @import("std");
const ShapeVector = struct {
    v: [6]f32,
    fn zero() ShapeVector {
        return .{ .v = @splat(0) };
    }
};
const MeasuredChar = struct { char: u8, v: [6]f32 };
const measured_ascii = [_]MeasuredChar{
    .{ .char = ' ', .v = .{ 0, 0, 0, 0, 0, 0 } },
    .{ .char = '!', .v = .{ 0.017, 0.010, 0.066, 0.047, 0.004, 0.001 } },
    .{ .char = '"', .v = .{ 0.126, 0.121, 0.004, 0.003, 0, 0 } },
    .{ .char = '#', .v = .{ 0.060, 0.077, 0.323, 0.295, 0.046, 0.020 } },
    .{ .char = '$', .v = .{ 0.147, 0.163, 0.176, 0.288, 0.089, 0.095 } },
    .{ .char = '%', .v = .{ 0.159, 0.086, 0.281, 0.264, 0.051, 0.089 } },
    .{ .char = '&', .v = .{ 0.120, 0.065, 0.315, 0.284, 0.071, 0.037 } },
    .{ .char = '\'', .v = .{ 0.037, 0.030, 0, 0, 0, 0 } },
    .{ .char = '*', .v = .{ 0, 0, 0.298, 0.283, 0, 0 } },
    .{ .char = '+', .v = .{ 0, 0, 0.182, 0.164, 0, 0 } },
    .{ .char = ',', .v = .{ 0, 0, 0, 0, 0.105, 0.025 } },
    .{ .char = '.', .v = .{ 0, 0, 0, 0, 0.009, 0.005 } },
    .{ .char = '/', .v = .{ 0, 0.156, 0.138, 0.054, 0.112, 0 } },
    .{ .char = '[', .v = .{ 0.175, 0.078, 0.200, 0, 0.130, 0.077 } },
    .{ .char = ']', .v = .{ 0.083, 0.168, 0, 0.193, 0.081, 0.122 } },
    .{ .char = '|', .v = .{ 0.049, 0.036, 0.063, 0.047, 0.025, 0.017 } },
    .{ .char = '(', .v = .{ 0.096, 0.078, 0.254, 0, 0.021, 0.064 } },
    .{ .char = ')', .v = .{ 0.083, 0.083, 0, 0.249, 0.069, 0.014 } },
    .{ .char = ':', .v = .{ 0, 0, 0.041, 0.033, 0.007, 0.003 } },
    .{ .char = ';', .v = .{ 0, 0, 0.041, 0.033, 0.106, 0.023 } },
    .{ .char = '<', .v = .{ 0, 0.013, 0.234, 0.033, 0, 0.017 } },
    .{ .char = '=', .v = .{ 0, 0, 0.208, 0.199, 0, 0 } },
    .{ .char = '>', .v = .{ 0.013, 0, 0.040, 0.230, 0.017, 0 } },
    .{ .char = '?', .v = .{ 0.116, 0.115, 0.078, 0.135, 0.015, 0 } },
    .{ .char = '@', .v = .{ 0.165, 0.132, 0.269, 0.374, 0.132, 0.176 } },
    .{ .char = '\\', .v = .{ 0.157, 0, 0.066, 0.122, 0, 0.111 } },
    .{ .char = '^', .v = .{ 0.184, 0.180, 0, 0, 0, 0 } },
    .{ .char = '`', .v = .{ 0.067, 0.051, 0, 0, 0, 0 } },
    .{ .char = '{', .v = .{ 0.056, 0.099, 0.159, 0.039, 0.027, 0.085 } },
    .{ .char = '}', .v = .{ 0.109, 0.045, 0.049, 0.149, 0.090, 0.019 } },
    .{ .char = '~', .v = .{ 0, 0, 0.176, 0.170, 0, 0 } },
    .{ .char = '-', .v = .{ 0, 0, 0.128, 0.124, 0, 0 } },
    .{ .char = '_', .v = .{ 0, 0, 0, 0, 0.156, 0.152 } },
    // Numbers
    .{ .char = '0', .v = .{ 0.113, 0.104, 0.377, 0.320, 0.040, 0.035 } },
    .{ .char = '1', .v = .{ 0.065, 0.030, 0.018, 0.123, 0.067, 0.085 } },
    .{ .char = '2', .v = .{ 0.135, 0.087, 0.068, 0.181, 0.100, 0.069 } },
    .{ .char = '3', .v = .{ 0.118, 0.093, 0.046, 0.282, 0.087, 0.026 } },
    .{ .char = '4', .v = .{ 0.020, 0.004, 0.275, 0.236, 0, 0.038 } },
    .{ .char = '5', .v = .{ 0.131, 0.087, 0.149, 0.243, 0.073, 0.032 } },
    .{ .char = '6', .v = .{ 0.089, 0.079, 0.334, 0.253, 0.040, 0.043 } },
    .{ .char = '7', .v = .{ 0.108, 0.144, 0.044, 0.145, 0.037, 0 } },
    .{ .char = '8', .v = .{ 0.117, 0.116, 0.324, 0.319, 0.061, 0.054 } },
    .{ .char = '9', .v = .{ 0.128, 0.104, 0.230, 0.330, 0.055, 0 } },
    // Uppercase
    .{ .char = 'A', .v = .{ 0.036, 0.030, 0.301, 0.305, 0.054, 0.058 } },
    .{ .char = 'B', .v = .{ 0.153, 0.107, 0.349, 0.329, 0.086, 0.039 } },
    .{ .char = 'C', .v = .{ 0.089, 0.137, 0.289, 0.001, 0.018, 0.104 } },
    .{ .char = 'D', .v = .{ 0.161, 0.094, 0.284, 0.305, 0.093, 0.016 } },
    .{ .char = 'E', .v = .{ 0.133, 0.111, 0.324, 0.096, 0.068, 0.091 } },
    .{ .char = 'F', .v = .{ 0.122, 0.127, 0.306, 0.111, 0.049, 0 } },
    .{ .char = 'G', .v = .{ 0.108, 0.124, 0.304, 0.269, 0.044, 0.086 } },
    .{ .char = 'H', .v = .{ 0.096, 0.096, 0.361, 0.354, 0.055, 0.055 } },
    .{ .char = 'I', .v = .{ 0.104, 0.100, 0.075, 0.061, 0.078, 0.074 } },
    .{ .char = 'J', .v = .{ 0.044, 0.144, 0, 0.273, 0.087, 0.024 } },
    .{ .char = 'K', .v = .{ 0.096, 0.101, 0.371, 0.134, 0.055, 0.069 } },
    .{ .char = 'L', .v = .{ 0.091, 0, 0.263, 0, 0.061, 0.099 } },
    .{ .char = 'M', .v = .{ 0.148, 0.147, 0.422, 0.414, 0.052, 0.053 } },
    .{ .char = 'N', .v = .{ 0.144, 0.090, 0.332, 0.357, 0.051, 0.078 } },
    .{ .char = 'O', .v = .{ 0.124, 0.120, 0.296, 0.294, 0.048, 0.042 } },
    .{ .char = 'P', .v = .{ 0.139, 0.132, 0.335, 0.241, 0.053, 0 } },
    .{ .char = 'Q', .v = .{ 0.124, 0.120, 0.294, 0.291, 0.049, 0.211 } },
    .{ .char = 'R', .v = .{ 0.150, 0.123, 0.350, 0.322, 0.056, 0.066 } },
    .{ .char = 'S', .v = .{ 0.136, 0.116, 0.180, 0.253, 0.088, 0.052 } },
    .{ .char = 'T', .v = .{ 0.149, 0.142, 0.077, 0.056, 0.002, 0.001 } },
    .{ .char = 'U', .v = .{ 0.096, 0.097, 0.283, 0.286, 0.051, 0.045 } },
    .{ .char = 'V', .v = .{ 0.102, 0.096, 0.239, 0.223, 0.003, 0.001 } },
    .{ .char = 'W', .v = .{ 0.096, 0.089, 0.418, 0.402, 0.075, 0.070 } },
    .{ .char = 'X', .v = .{ 0.102, 0.095, 0.226, 0.210, 0.059, 0.063 } },
    .{ .char = 'Y', .v = .{ 0.105, 0.099, 0.181, 0.163, 0.002, 0.001 } },
    .{ .char = 'Z', .v = .{ 0.107, 0.167, 0.168, 0.086, 0.102, 0.094 } },
    // Lowercase
    .{ .char = 'a', .v = .{ 0, 0, 0.225, 0.292, 0.082, 0.058 } },
    .{ .char = 'b', .v = .{ 0.133, 0, 0.295, 0.288, 0.068, 0.050 } },
    .{ .char = 'c', .v = .{ 0, 0, 0.269, 0.055, 0.028, 0.074 } },
    .{ .char = 'd', .v = .{ 0, 0.132, 0.286, 0.286, 0.061, 0.057 } },
    .{ .char = 'e', .v = .{ 0, 0, 0.335, 0.247, 0.038, 0.063 } },
    .{ .char = 'f', .v = .{ 0.039, 0.136, 0.222, 0.067, 0.013, 0 } },
    .{ .char = 'g', .v = .{ 0, 0.008, 0.285, 0.227, 0.192, 0.261 } },
    .{ .char = 'h', .v = .{ 0.132, 0, 0.296, 0.265, 0.054, 0.053 } },
    .{ .char = 'i', .v = .{ 0.047, 0.041, 0.061, 0.108, 0.066, 0.082 } },
    .{ .char = 'j', .v = .{ 0.001, 0.094, 0.026, 0.231, 0.124, 0.133 } },
    .{ .char = 'k', .v = .{ 0.133, 0, 0.352, 0.187, 0.053, 0.067 } },
    .{ .char = 'l', .v = .{ 0.165, 0.001, 0.150, 0.006, 0, 0.078 } },
    .{ .char = 'm', .v = .{ 0, 0, 0.346, 0.327, 0.051, 0.050 } },
    .{ .char = 'n', .v = .{ 0, 0, 0.294, 0.269, 0.054, 0.053 } },
    .{ .char = 'o', .v = .{ 0, 0, 0.275, 0.272, 0.047, 0.041 } },
    .{ .char = 'p', .v = .{ 0, 0, 0.293, 0.283, 0.219, 0.049 } },
    .{ .char = 'q', .v = .{ 0, 0, 0.280, 0.285, 0.062, 0.207 } },
    .{ .char = 'r', .v = .{ 0, 0, 0.253, 0.131, 0.073, 0.009 } },
    .{ .char = 's', .v = .{ 0, 0, 0.216, 0.208, 0.081, 0.045 } },
    .{ .char = 't', .v = .{ 0.033, 0, 0.235, 0.022, 0.000, 0.085 } },
    .{ .char = 'u', .v = .{ 0, 0, 0.271, 0.269, 0.067, 0.053 } },
    .{ .char = 'v', .v = .{ 0, 0, 0.244, 0.231, 0.004, 0.002 } },
    .{ .char = 'w', .v = .{ 0, 0, 0.380, 0.374, 0.071, 0.071 } },
    .{ .char = 'x', .v = .{ 0, 0, 0.247, 0.230, 0.059, 0.061 } },
    .{ .char = 'y', .v = .{ 0, 0, 0.247, 0.234, 0.143, 0.017 } },
    .{ .char = 'z', .v = .{ 0, 0, 0.114, 0.190, 0.082, 0.072 } },
};

/// Measure the shape of a character using real measured data when available
fn measureCharShape(char: []const u8) ShapeVector {
    // For space, return zero
    if (char.len == 1 and char[0] == ' ') {
        return ShapeVector.zero();
    }

    // Check measured ASCII data first (single-byte chars)
    if (char.len == 1) {
        const c = char[0];
        for (measured_ascii) |m| {
            if (m.char == c) {
                return .{ .v = m.v };
            }
        }
    }

    // Decode UTF-8 to get codepoint for Unicode chars
    const codepoint = std.unicode.utf8Decode(char) catch return ShapeVector.zero();

    // Unicode characters - use computed/estimated values
    return switch (codepoint) {
        // Box drawing - horizontal
        '─', '━' => .{ .v = .{ 0.0, 0.0, 0.3, 0.3, 0.0, 0.0 } },
        '╌', '╍' => .{ .v = .{ 0.0, 0.0, 0.2, 0.2, 0.0, 0.0 } },

        // Box drawing - vertical (thin line down center)
        '│', '┃' => .{ .v = .{ 0.05, 0.04, 0.06, 0.05, 0.02, 0.02 } }, // Based on | measurement
        '╎', '╏' => .{ .v = .{ 0.03, 0.03, 0.0, 0.0, 0.03, 0.03 } },

        // Corners - light
        '┌' => .{ .v = .{ 0.0, 0.0, 0.06, 0.15, 0.03, 0.0 } },
        '┐' => .{ .v = .{ 0.0, 0.0, 0.15, 0.06, 0.0, 0.03 } },
        '└' => .{ .v = .{ 0.03, 0.0, 0.06, 0.15, 0.0, 0.0 } },
        '┘' => .{ .v = .{ 0.0, 0.03, 0.15, 0.06, 0.0, 0.0 } },

        // Rounded corners
        '╭' => .{ .v = .{ 0.0, 0.0, 0.04, 0.12, 0.05, 0.0 } },
        '╮' => .{ .v = .{ 0.0, 0.0, 0.12, 0.04, 0.0, 0.05 } },
        '╰' => .{ .v = .{ 0.05, 0.0, 0.04, 0.12, 0.0, 0.0 } },
        '╯' => .{ .v = .{ 0.0, 0.05, 0.12, 0.04, 0.0, 0.0 } },

        // T-junctions
        '├' => .{ .v = .{ 0.03, 0.0, 0.06, 0.15, 0.03, 0.0 } },
        '┤' => .{ .v = .{ 0.0, 0.03, 0.15, 0.06, 0.0, 0.03 } },
        '┬' => .{ .v = .{ 0.0, 0.0, 0.15, 0.15, 0.03, 0.03 } },
        '┴' => .{ .v = .{ 0.03, 0.03, 0.15, 0.15, 0.0, 0.0 } },
        '┼' => .{ .v = .{ 0.03, 0.03, 0.15, 0.15, 0.03, 0.03 } },

        // Diagonals - based on / and \ measurements
        '╱' => .{ .v = .{ 0.0, 0.156, 0.138, 0.054, 0.112, 0.0 } }, // Same as /
        '╲' => .{ .v = .{ 0.157, 0.0, 0.066, 0.122, 0.0, 0.111 } }, // Same as \
        '╳' => .{ .v = .{ 0.08, 0.08, 0.10, 0.09, 0.06, 0.06 } },

        // Shade characters - uniform density
        '░' => .{ .v = .{ 0.25, 0.25, 0.25, 0.25, 0.25, 0.25 } },
        '▒' => .{ .v = .{ 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 } },
        '▓' => .{ .v = .{ 0.75, 0.75, 0.75, 0.75, 0.75, 0.75 } },
        '█' => .{ .v = .{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 } },

        // Half blocks
        '▀' => .{ .v = .{ 1.0, 1.0, 0.5, 0.5, 0.0, 0.0 } },
        '▄' => .{ .v = .{ 0.0, 0.0, 0.5, 0.5, 1.0, 1.0 } },
        '▌' => .{ .v = .{ 1.0, 0.0, 1.0, 0.0, 1.0, 0.0 } },
        '▐' => .{ .v = .{ 0.0, 1.0, 0.0, 1.0, 0.0, 1.0 } },

        // Quadrant blocks - 2x2 sub-pixel patterns
        // Our shape regions are 2x3, quadrants are 2x2, so we map:
        // top-left quadrant -> regions 0,2 (left column, top 2/3)
        // top-right quadrant -> regions 1,3 (right column, top 2/3)
        // bottom-left quadrant -> regions 2,4 (left column, bottom 2/3)
        // bottom-right quadrant -> regions 3,5 (right column, bottom 2/3)
        '▘' => .{ .v = .{ 1.0, 0.0, 0.5, 0.0, 0.0, 0.0 } }, // top-left
        '▝' => .{ .v = .{ 0.0, 1.0, 0.0, 0.5, 0.0, 0.0 } }, // top-right
        '▖' => .{ .v = .{ 0.0, 0.0, 0.5, 0.0, 1.0, 0.0 } }, // bottom-left
        '▗' => .{ .v = .{ 0.0, 0.0, 0.0, 0.5, 0.0, 1.0 } }, // bottom-right
        '▚' => .{ .v = .{ 1.0, 0.0, 0.5, 0.5, 0.0, 1.0 } }, // TL + BR diagonal
        '▞' => .{ .v = .{ 0.0, 1.0, 0.5, 0.5, 1.0, 0.0 } }, // TR + BL diagonal
        '▛' => .{ .v = .{ 1.0, 1.0, 1.0, 0.5, 1.0, 0.0 } }, // missing BR
        '▜' => .{ .v = .{ 1.0, 1.0, 0.5, 1.0, 0.0, 1.0 } }, // missing BL
        '▙' => .{ .v = .{ 1.0, 0.0, 1.0, 0.5, 1.0, 1.0 } }, // missing TR
        '▟' => .{ .v = .{ 0.0, 1.0, 0.5, 1.0, 1.0, 1.0 } }, // missing TL

        // Braille patterns (U+2800-U+28FF) - compute from dot pattern
        0x2800...0x28FF => |cp| blk: {
            const pattern = cp - 0x2800;
            // Braille dot layout:    1 4
            //                        2 5
            //                        3 6
            //                        7 8
            // Map to our 6 regions (2x3):
            const dot1: f32 = if (pattern & 0x01 != 0) 1.0 else 0.0; // top-left
            const dot2: f32 = if (pattern & 0x02 != 0) 1.0 else 0.0; // mid-left upper
            const dot3: f32 = if (pattern & 0x04 != 0) 1.0 else 0.0; // mid-left lower
            const dot4: f32 = if (pattern & 0x08 != 0) 1.0 else 0.0; // top-right
            const dot5: f32 = if (pattern & 0x10 != 0) 1.0 else 0.0; // mid-right upper
            const dot6: f32 = if (pattern & 0x20 != 0) 1.0 else 0.0; // mid-right lower
            const dot7: f32 = if (pattern & 0x40 != 0) 1.0 else 0.0; // bottom-left
            const dot8: f32 = if (pattern & 0x80 != 0) 1.0 else 0.0; // bottom-right

            break :blk ShapeVector{
                .v = .{
                    dot1, // region 0: top-left
                    dot4, // region 1: top-right
                    (dot2 + dot3) / 2.0, // region 2: middle-left
                    (dot5 + dot6) / 2.0, // region 3: middle-right
                    dot7, // region 4: bottom-left
                    dot8, // region 5: bottom-right
                },
            };
        },

        else => ShapeVector.zero(),
    };
}

const ascii_chars = [_][]const u8{ " ", ".", "'", "`", "-", "_", "|", "/", "\\", "+", ":", "*" };
const unicode_box_chars = [_][]const u8{ " ", "─", "│", "┌", "┐", "└", "┘", "├", "┤", "┬", "┴", "┼", "╱", "╲", "╳", "╭", "╮", "╰", "╯" };
const unicode_block_chars = [_][]const u8{ " ", "░", "▒", "▓", "█", "▀", "▄", "▌", "▐", "▖", "▗", "▘", "▝", "▚", "▞" };

// Shade characters - simple uniform density gradient (5 levels)
const shade_chars = [_][]const u8{ " ", "░", "▒", "▓", "█" };

// Quadrant blocks in Bayer dither order (2x2 matrix: 0=TL, 1=BR, 2=TR, 3=BL)
// Gives 5 brightness levels with ordered dithering pattern
const quadrant_chars = [_][]const u8{
    " ", // 0/4 - empty
    "▘", // 1/4 - top-left only
    "▚", // 2/4 - top-left + bottom-right (diagonal)
    "▜", // 3/4 - missing bottom-left
    "█", // 4/4 - full
};

// All 16 quadrant combinations for full 2x2 sub-pixel rendering
// Index is a 4-bit mask: bit 3=TL, bit 2=TR, bit 1=BL, bit 0=BR
const quadrant_all_chars = [_][]const u8{
    " ", // 0000
    "▗", // 0001 - bottom-right
    "▖", // 0010 - bottom-left
    "▄", // 0011 - bottom half
    "▝", // 0100 - top-right
    "▐", // 0101 - right half
    "▞", // 0110 - top-right + bottom-left
    "▟", // 0111 - missing top-left
    "▘", // 1000 - top-left
    "▚", // 1001 - top-left + bottom-right
    "▌", // 1010 - left half
    "▙", // 1011 - missing top-right
    "▀", // 1100 - top half
    "▜", // 1101 - missing bottom-left
    "▛", // 1110 - missing bottom-right
    "█", // 1111 - full
};

pub const max_cols = 240;
pub const max_rows = 80;
pub const max_text_bytes = max_rows * (max_cols * 4 + 1);
pub const max_bytes = max_text_bytes + max_cols * max_rows * 6;
fn byte(v: f32) u8 {
    return @intFromFloat(@round(@max(0, @min(255, v))));
}
const Candidate = struct { cp: u21, v: [6]f32 };
pub const Converter = struct {
    candidates: [351]Candidate = undefined,
    count: usize = 0,
    charset: u32 = 0,
    fn add(self: *Converter, cp: u21) void {
        var bytes: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &bytes) catch unreachable;
        self.candidates[self.count] = .{ .cp = cp, .v = measureCharShape(bytes[0..n]).v };
        self.count += 1;
    }
    fn set(self: *Converter, charset: u32) void {
        if (self.charset == charset) return;
        self.charset = charset;
        self.count = 0;
        const chars: []const []const u8 = switch (charset) {
            1 => &ascii_chars,
            2 => &shade_chars,
            3 => &quadrant_chars,
            6 => &unicode_box_chars,
            7 => &unicode_block_chars,
            else => &.{},
        };
        for (chars) |char| self.add(std.unicode.utf8Decode(char) catch unreachable);
        if (charset == 4 or charset == 5 or charset == 8) {
            for (0..256) |i| self.add(@intCast(0x2800 + i));
            if (charset == 4) {
                for (" .,'` :;!?\"-_ij") |ch| self.add(ch);
            } else if (charset == 5) for (32..127) |ch| self.add(@intCast(ch));
        }
    }
    fn match(self: *const Converter, shape: [6]f32) u21 {
        var best: f32 = std.math.inf(f32);
        var cp: u21 = ' ';
        for (self.candidates[0..self.count]) |candidate| {
            var distance: f32 = 0;
            for (shape, candidate.v) |a, b| distance += (a - b) * (a - b);
            if (distance < best) {
                best = distance;
                cp = candidate.cp;
            }
        }
        return cp;
    }
    const Colored = struct { cp: u21, colors: [6]u8 };
    fn coloredBlock(self: *const Converter, rgb: [6][3]f32) Colored {
        var best: f32 = std.math.inf(f32);
        var result: Colored = .{ .cp = ' ', .colors = @splat(0) };
        for (self.candidates[0..self.count]) |candidate| {
            var sw: f32 = 0;
            var sww: f32 = 0;
            for (candidate.v) |w| {
                sw += w;
                sww += w * w;
            }
            const den = 6 * sww - sw * sw;
            var colors: [6]u8 = undefined;
            for (0..3) |channel| {
                var sum: f32 = 0;
                var weighted: f32 = 0;
                for (rgb, candidate.v) |pixel, w| {
                    sum += pixel[channel];
                    weighted += pixel[channel] * w;
                }
                const bg = if (den < 0.0001) sum / 6 else (sum * sww - weighted * sw) / den;
                const fg = if (den < 0.0001) bg else bg + (6 * weighted - sw * sum) / den;
                colors[channel] = byte(fg);
                colors[channel + 3] = byte(bg);
            }
            var err: f32 = 0;
            for (rgb, candidate.v) |pixel, w| for (0..3) |channel| {
                const predicted = @as(f32, @floatFromInt(colors[channel])) * w + @as(f32, @floatFromInt(colors[channel + 3])) * (1 - w);
                err += (pixel[channel] - predicted) * (pixel[channel] - predicted);
            };
            if (err < best) {
                best = err;
                result = .{ .cp = candidate.cp, .colors = colors };
            }
        }
        return result;
    }
    pub fn render(self: *Converter, pixels: []const u8, cols: usize, rows: usize, charset: u32, tone: u32, out: []u8) usize {
        std.debug.assert(cols > 0 and cols <= max_cols and rows > 0 and rows <= max_rows and charset >= 1 and charset <= 8);
        self.set(charset);
        var length: usize = 0;
        for (0..rows) |y| {
            for (0..cols) |x| {
                var shape: [6]f32 = undefined;
                var rgb: [6][3]f32 = undefined;
                var dark_rgb: [3]f32 = @splat(0);
                var dark_count: f32 = 0;
                for (0..3) |ry| for (0..2) |rx| {
                    // Area sampling keeps thin edges when reducing the native frame.
                    const sx = (x * 2 + rx) * 240 / (cols * 2);
                    const sy = (y * 3 + ry) * 160 / (rows * 3);
                    const ex = @min(240, @max(sx + 1, (x * 2 + rx + 1) * 240 / (cols * 2)));
                    const ey = @min(160, @max(sy + 1, (y * 3 + ry + 1) * 160 / (rows * 3)));
                    var sum: f32 = 0;
                    var channels: [3]f32 = @splat(0);
                    var samples: f32 = 0;
                    for (sy..ey) |py| for (sx..ex) |px| {
                        const i = (py * 240 + px) * 4;
                        if (tone == 6 and @max(pixels[i], pixels[i + 1], pixels[i + 2]) <= 180) {
                            for (0..3) |channel| dark_rgb[channel] += @floatFromInt(pixels[i + channel]);
                            dark_count += 1;
                            samples += 1;
                            continue;
                        }
                        sum += if (tone == 4 or tone == 5 or tone == 6) @as(f32, @floatFromInt(@max(pixels[i], pixels[i + 1], pixels[i + 2]))) / 255 else (@as(f32, @floatFromInt(pixels[i])) * 0.299 + @as(f32, @floatFromInt(pixels[i + 1])) * 0.587 + @as(f32, @floatFromInt(pixels[i + 2])) * 0.114) / 255;
                        for (0..3) |channel| channels[channel] += @floatFromInt(pixels[i + channel]);
                        samples += 1;
                    };
                    // Suppress the lab background vignette instead of filling it with faint strokes.
                    const value = sum / samples;
                    shape[ry * 2 + rx] = if (value < 0.09) 0 else value;
                    for (0..3) |channel| rgb[ry * 2 + rx][channel] = if (value < 0.09) 0 else channels[channel] / samples;
                };
                var colors: [6]u8 = .{ 255, 255, 255, 0, 0, 0 };
                var cp = self.match(shape);
                if (tone < 2 or tone == 4 or tone == 5 or tone == 6) {
                    if ((charset == 3 or charset == 7) and tone < 5) {
                        const block = self.coloredBlock(rgb);
                        cp = block.cp;
                        colors = block.colors;
                    } else {
                        var sum: [3]f32 = @splat(0);
                        var count: f32 = 0;
                        for (rgb, shape) |pixel, ink| if (ink > 0) {
                            for (0..3) |channel| sum[channel] += pixel[channel];
                            count += 1;
                        };
                        for (0..3) |channel| colors[channel] = byte(sum[channel] / @max(1, count));
                    }
                }
                if (tone == 6) for (0..3) |channel| {
                    colors[channel + 3] = byte(dark_rgb[channel] / @max(1, dark_count));
                };
                const color_offset = max_text_bytes + (y * cols + x) * 6;
                @memcpy(out[color_offset..][0..6], &colors);
                var bytes: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cp, &bytes) catch unreachable;
                @memcpy(out[length..][0..n], bytes[0..n]);
                length += n;
            }
            out[length] = '\n';
            length += 1;
        }
        const color_len = cols * rows * 6;
        std.mem.copyForwards(u8, out[length..][0..color_len], out[max_text_bytes..][0..color_len]);
        return length + color_len;
    }
};
test "glyph sets produce valid bounded text and distinguish ink from blank" {
    var converter: Converter = .{};
    var pixels: [240 * 160 * 4]u8 = @splat(0);
    var output: [max_bytes]u8 = undefined;
    for (1..9) |set_id| {
        @memset(&pixels, 0);
        const blank_len = converter.render(&pixels, 20, 10, @intCast(set_id), 0, &output);
        try std.testing.expect(std.unicode.utf8ValidateSlice(output[0 .. blank_len - 1200]));
        const blank = std.hash.Wyhash.hash(0, output[0..blank_len]);
        @memset(&pixels, 20);
        const dark_len = converter.render(&pixels, 20, 10, @intCast(set_id), 0, &output);
        try std.testing.expectEqual(blank, std.hash.Wyhash.hash(0, output[0..dark_len]));
        @memset(&pixels, 255);
        const ink_len = converter.render(&pixels, 20, 10, @intCast(set_id), 0, &output);
        try std.testing.expect(blank != std.hash.Wyhash.hash(0, output[0..ink_len]));
        try std.testing.expectEqual(@as(usize, 10), std.mem.count(u8, output[0 .. ink_len - 1200], "\n"));
    }
}

test "glyph foreground preserves color and monochrome modes use neutral colors" {
    var converter: Converter = .{};
    var pixels: [240 * 160 * 4]u8 = undefined;
    for (0..240 * 160) |i| @memcpy(pixels[i * 4 ..][0..4], &[_]u8{ 210, 90, 35, 255 });
    var output: [max_bytes]u8 = undefined;
    for (1..9) |set_id| {
        const len = converter.render(&pixels, 1, 1, @intCast(set_id), 0, &output);
        const colors = output[len - 6 .. len];
        try std.testing.expect(colors[0] > colors[2] or colors[3] > colors[5]);
        const colored_len = converter.render(&pixels, 1, 1, @intCast(set_id), 4, &output);
        const tinted = output[colored_len - 6 .. colored_len];
        try std.testing.expect(tinted[0] > tinted[2] or tinted[3] > tinted[5]);
        const mono_len = converter.render(&pixels, 1, 1, @intCast(set_id), 3, &output);
        try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 0, 0, 0 }, output[mono_len - 6 .. mono_len]);
    }
}
test "blocks preserve two distinct source colors" {
    var converter: Converter = .{};
    var pixels: [240 * 160 * 4]u8 = undefined;
    for (0..160) |y| for (0..240) |x| {
        const color = [4]u8{ if (x < 120) 255 else 0, if (x < 120) 0 else 255, 0, 255 };
        @memcpy(pixels[(y * 240 + x) * 4 ..][0..4], &color);
    };
    var output: [max_bytes]u8 = undefined;
    const len = converter.render(&pixels, 1, 1, 7, 0, &output);
    const colors = output[len - 6 .. len];
    try std.testing.expect((colors[0] > 240 and colors[4] > 240) or (colors[1] > 240 and colors[3] > 240));
}

test "wash keeps monochrome glyph selection for every charset" {
    var converter: Converter = .{};
    var mono: [240 * 160 * 4]u8 = undefined;
    var tint: [240 * 160 * 4]u8 = undefined;
    for (0..240 * 160) |i| {
        const ink: u8 = if (i % 7 < 3) 255 else 0;
        @memcpy(mono[i * 4 ..][0..4], &[_]u8{ ink, ink, ink, 255 });
        @memcpy(tint[i * 4 ..][0..4], &[_]u8{ ink, ink / 2, ink / 4, 255 });
    }
    var a: [max_bytes]u8 = undefined;
    var b: [max_bytes]u8 = undefined;
    for (1..9) |charset| {
        const alen = converter.render(&mono, 20, 10, @intCast(charset), 3, &a);
        const blen = converter.render(&tint, 20, 10, @intCast(charset), 5, &b);
        try std.testing.expectEqualSlices(u8, a[0 .. alen - 1200], b[0 .. blen - 1200]);
    }
}

test "two-shade glyphs retain wash shapes and add a dim background" {
    var converter: Converter = .{};
    var wash: [240 * 160 * 4]u8 = undefined;
    var shaded: [240 * 160 * 4]u8 = undefined;
    for (0..240 * 160) |i| {
        const ink: u8 = if (i % 7 < 3) 255 else 0;
        @memcpy(wash[i * 4 ..][0..4], &[_]u8{ ink, ink / 2, ink / 4, 255 });
        const shade: u8 = if (ink == 0) 80 else ink;
        @memcpy(shaded[i * 4 ..][0..4], &[_]u8{ shade, shade / 2, shade / 4, 255 });
    }
    var a: [max_bytes]u8 = undefined;
    var b: [max_bytes]u8 = undefined;
    for (1..9) |charset| {
        const alen = converter.render(&wash, 20, 10, @intCast(charset), 5, &a);
        const blen = converter.render(&shaded, 20, 10, @intCast(charset), 6, &b);
        try std.testing.expectEqualSlices(u8, a[0 .. alen - 1200], b[0 .. blen - 1200]);
        try std.testing.expect(b[blen - 3] > b[blen - 1] and b[blen - 3] > 0);
    }
}
