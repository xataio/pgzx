const std = @import("std");

// Load pgzx build support. The build utilities use pg_config to find all dependencies
// and provide functions go create and test extensions.
const PGBuild = @import("pgzx").Build;

pub fn build(b: *std.Build) void {
    const NAME = "pghostname_zig";
    const VERSION = PGBuild.ExtensionVersion{ .major = 0, .minor = 1 };

    const DB_TEST_USER = "postgres";
    const DB_TEST_PORT = 5432;

    const build_options = b.addOptions();
    build_options.addOption(bool, "testfn", b.option(bool, "testfn", "Register test function") orelse false);

    var proj = PGBuild.Project.init(b, .{
        .name = NAME,
        .version = VERSION,
        .root_dir = "src/",
        .root_source_file = "src/main.zig",
    });
    proj.addOptions("build_options", build_options);

    const steps = .{
        .check = b.step("check", "Check if project compiles"),
        .install = b.getInstallStep(),
        .pg_regress = b.step("pg_regress", "Run regression tests"),
        .unit = b.step("unit", "Run unit tests"),
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
        var regress = proj.pgbuild.addRegress(.{
            .db_user = DB_TEST_USER,
            .db_port = DB_TEST_PORT,
            .root_dir = ".",
            .scripts = &[_][]const u8{
                "pghostname_zig_test",
            },
        });
        regress.step.dependOn(steps.install);

        steps.pg_regress.dependOn(&regress.step);
    }

    { // unit testing. We install an alternative version of the lib build with test_fn = true
        const test_options = b.addOptions();
        test_options.addOption(bool, "testfn", true);

        const lib = proj.extensionLib();
        lib.root_module.addOptions("build_options", test_options);

        // Step for running the unit tests.
        const psql_run_tests = proj.pgbuild.addRunTests(.{
            .name = NAME,
            .db_user = DB_TEST_USER,
            .db_port = DB_TEST_PORT,
        });

        // Build and install extension before running the tests.
        psql_run_tests.step.dependOn(&proj.pgbuild.addInstallExtensionLibArtifact(lib, NAME).step);
        psql_run_tests.step.dependOn(&proj.installExtensionLib().step);

        steps.unit.dependOn(&psql_run_tests.step);
    }
}
