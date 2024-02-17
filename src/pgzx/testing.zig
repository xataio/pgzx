const std = @import("std");
pub const elog = @import("elog.zig");
pub const fmgr = @import("fmgr.zig");

fn runTests(comptime T: type) type {
    return struct {
        fn run_tests() !u32 {
            var success_count: u32 = 0;

            inline for (@typeInfo(T).Struct.decls) |f| {
                if (std.mem.startsWith(u8, f.name, "test")) {
                    elog.Info(@src(), "Running test: {s}\n", .{f.name});

                    const fun = @field(T, f.name);
                    fun() catch |err| {
                        return elog.Error(@src(), "Test failed: {}\n", .{err});
                    };
                    success_count += 1;
                }
            }

            if (success_count > 0) {
                elog.Info(@src(), "All tests passed\n", .{});
            } else {
                elog.Info(@src(), "No tests found\n", .{});
            }

            return success_count;
        }
    };
}

pub inline fn registerTests(comptime T: type, comptime testfn: bool) void {
    if (testfn) {
        fmgr.PG_FUNCTION_V1("run_tests", runTests(T).run_tests);
    }
}
