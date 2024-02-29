const pgzx = @import("pgzx.zig");

comptime {
    pgzx.PG_MODULE_MAGIC();

    pgzx.testing.registerTests(
        @import("build_options").testfn,
        .{
            pgzx.collections.list.PointerListTestSuite,
        },
    );
}
