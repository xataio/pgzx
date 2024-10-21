const std = @import("std");
const pgzx = @import("pgzx");

comptime {
    pgzx.PG_MODULE_MAGIC();

    pgzx.PG_FUNCTION_V1("pghostname_zig", pghostname_zig);
}

fn pghostname_zig() ![]const u8 {
    var buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = try std.posix.gethostname(&buffer);
    pgzx.elog.Info(@src(), "hostname: {s}\n", .{hostname});
    return hostname;
}

const Testsuite1 = struct {
    pub fn testHappyPath() !void {
        const hostname = try pghostname_zig();
        try std.testing.expect(hostname.len > 0);
    }
};

comptime {
    pgzx.testing.registerTests(
        @import("build_options").testfn,
        .{Testsuite1},
    );
}
