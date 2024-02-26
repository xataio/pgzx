const std = @import("std");
pub const elog = @import("elog.zig");
pub const fmgr = @import("fmgr.zig");
pub const mem = @import("mem.zig");
pub const pg = @import("c.zig");
pub const pgzx_err = @import("err.zig");

fn runTests(comptime testsuites: anytype) type {
    return struct {
        fn run_tests() !u32 {
            var success_count: u32 = 0;

            inline for (testsuites) |T| {
                inline for (@typeInfo(T).Struct.decls) |f| {
                    if (std.mem.startsWith(u8, f.name, "test")) {
                        elog.Info(@src(), "Running test: {s}\n", .{f.name});
                        const fun = @field(T, f.name);

                        // create a memory context for the test
                        var test_memctx = try mem.createTempAllocSet("test_memory_context", .{ .parent = pg.CurrentMemoryContext });
                        defer test_memctx.deinit();

                        // capture PG errors in case some test does throw a PG error that we don't want to leak:
                        var errctx = pgzx_err.Context.init();
                        defer errctx.deinit();

                        if (errctx.pg_try()) {
                            fun() catch |err| {
                                return elog.Error(@src(), "Test failed: {}\n", .{err});
                            };
                        } else {
                            return elog.Error(@src(), "Test failed with Postgres error report: {}\n", .{errctx.errorValue()});
                        }

                        success_count += 1;
                    }
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

/// This function registers a set of test suites to be run inside the Postgres server. A `run_tests` function is
/// registered as a Postgres function that will run all the tests registered. This function is available over
/// SQL (`SELECT run_tests();`).
///
/// You would typically call this function like this:
///
/// ```
/// comptime {
///    pgzx.testing.registerTests(.{Tests}, @import("build_options").testfn);
///}
/// ```
///
/// The `build_options.testfn` options should be defined via `build.zig`. It is used to exclude the test function
/// from the production build.
///
/// If your extension has multiple modules, you can call `registerTests` like this to register the test suites
/// from all of them:
///
/// ```
/// comptime {
///    pgzx.testing.registerTests(.{
///         @import("module1.zig").Tests,
///         @import("module2.zig").Tests,
///         @import("module2.zig").Tests },
///     @import("build_options").testfn);
/// }
/// ```
///
/// Note that you can only call this function once in the extension.
pub inline fn registerTests(comptime testsuites: anytype, comptime testfn: bool) void {
    const T = @TypeOf(testsuites);
    if (@typeInfo(T) != .Struct) {
        @compileError("registerTests: testsuites must be an array of test suites. Found '" ++ @typeName(T) ++ "'");
    }

    if (testfn) {
        fmgr.PG_FUNCTION_V1("run_tests", runTests(testsuites).run_tests);
    }
}
