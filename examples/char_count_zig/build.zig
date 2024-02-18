const std = @import("std");

// Load pgzx build support. The build utilities use pg_config to find all dependencies
// and provide functions go create and test extensions.
const PGBuild = @import("pgzx").Build;

pub fn build(b: *std.Build) void {
    // Project meta data
    const name = "char_count_zig";
    const version = .{ .major = 0, .minor = 1 };

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Load the pgzx module and initialize the build utilities
    const dep_pgzx = b.dependency("pgzx", .{ .target = target, .optimize = optimize });
    const pgzx = dep_pgzx.module("pgzx");
    var pgbuild = PGBuild.create(b, .{ .target = target, .optimize = optimize });

    const build_options = b.addOptions();
    build_options.addOption(bool, "testfn", b.option(bool, "testfn", "Register test function") orelse false);

    // Register the dependency with the build system
    // and add pgzx as module dependency.
    const ext = pgbuild.addInstallExtension(.{
        .name = name,
        .version = version,
        .root_source_file = .{
            .path = "src/main.zig",
        },
        .root_dir = ".",
    });
    ext.lib.root_module.addImport("pgzx", pgzx);
    ext.lib.root_module.addOptions("build_options", build_options);

    b.getInstallStep().dependOn(&ext.step);

    // Configure pg_regress based testing for the current extension.
    const extest = pgbuild.addRegress(.{
        .db_user = "postgres",
        .db_port = 5432,
        .root_dir = ".",
        .scripts = &[_][]const u8{
            "char_count_test",
        },
    });

    // Make regression tests available to `zig build`
    var regress = b.step("pg_regress", "Run regression tests");
    regress.dependOn(&extest.step);

    // Extension build for unit tests. Same as above, but with testfn for sure true.
    const test_options = b.addOptions();
    test_options.addOption(bool, "testfn", true);
    const test_ext = pgbuild.addInstallExtension(.{
        .name = name,
        .version = version,
        .root_source_file = .{
            .path = "src/main.zig",
        },
        .root_dir = ".",
    });
    test_ext.lib.root_module.addImport("pgzx", pgzx);
    test_ext.lib.root_module.addOptions("build_options", test_options);

    // Step for running the unit tests.
    const psql_run_tests = pgbuild.addRunTests(.{
        .name = name,
        .db_user = "postgres",
        .db_port = 5432,
    });
    psql_run_tests.step.dependOn(&test_ext.step);

    var unit = b.step("unit", "Run unit tests");
    unit.dependOn(&psql_run_tests.step);
}
