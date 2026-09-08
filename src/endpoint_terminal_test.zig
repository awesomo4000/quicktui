comptime {
    _ = @import("quicktui");
}
extern "c" fn quicktui_endpoint_terminal_test() c_int;
pub fn main() !void {
    if (quicktui_endpoint_terminal_test() != 0) return error.EndpointStressFailed;
}
