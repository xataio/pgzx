const std = @import("std");
const pgzx = @import("pgzx");

comptime {
    pgzx.PG_MODULE_MAGIC();

    pgzx.PG_EXPORT(@This());
}

pub fn pghostname_zig() ![:0]const u8 {
    var buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&buffer) catch "unknown";
    return try pgzx.mem.PGCurrentContextAllocator.dupeZ(u8, hostname);
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
