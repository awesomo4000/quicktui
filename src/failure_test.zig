const runtime = @import("quicktui");

// Separate test artifact: the shipped CLI has no fault-injection switches.
pub fn main() !void {
    const source = @embedFile("counter.js") ++
        "\nsetTimeout(() => { throw new Error('intentional terminal test failure'); }, 30);";
    if (runtime.runCounter(source, false)) |_| {
        return error.ExpectedJavaScriptFailure;
    } else |err| {
        if (err != error.CounterFailed) return err;
    }
}
