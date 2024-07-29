const std = @import("std");

// Load pgzx build support. The build utilities use pg_config to find all dependencies
// and provide functions go create and test extensions.
const PGBuild = @import("pgzx").Build;

pub fn build(b: *std.Build) void {
    const NAME = "spi_sql";
    const VERSION = .{ .major = 0, .minor = 1 };

    const DB_TEST_USER = "postgres";
    const DB_TEST_PORT = 5432;

    const proj = PGBuild.Project.init(b, .{
        .name = NAME,
        .version = VERSION,
        .root_dir = "src/",
        .root_source_file = "src/main.zig",
    });

    const steps = .{
        .check = b.step("check", "Check if project compiles"),
        .install = b.getInstallStep(),
        .pg_regress = b.step("pg_regress", "Run regression tests"),
    };

    { // build and install extension
        steps.install.dependOn(&proj.installExtensionLib().step);
        steps.install.dependOn(&proj.installExtensionDir().step);
    }

    { // check extension Zig source code only. No linkage or installation for faster development.
        const lib = proj.extensionLib();
        lib.linkage = null;
        steps.check.dependOn(&lib.step);
    }

    { // pg_regress tests (regression tests use the default build)
        const regress = proj.pgbuild.addRegress(.{
            .db_user = DB_TEST_USER,
            .db_port = DB_TEST_PORT,
            .root_dir = ".",
            .scripts = &[_][]const u8{
                "char_count_test",
            },
        });
        regress.step.dependOn(steps.install);

        steps.pg_regress.dependOn(&regress.step);
    }
}
