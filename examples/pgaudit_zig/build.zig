const std = @import("std");

// Load pgzx build support. The build utilities use pg_config to find all dependencies
// and provide functions go create and test extensions.
const PGBuild = @import("pgzx").Build;

pub fn build(b: *std.Build) void {
    // Project meta data
    const name = "pg_audit_zig";
    const version = .{ .major = 0, .minor = 1 };

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Load the pgzx module and initialize the build utilities
    const dep_pgzx = b.dependency("pgzx", .{ .target = target, .optimize = optimize });
    const pgzx = dep_pgzx.module("pgzx");
    var pgbuild = PGBuild.create(b, .{ .target = target, .optimize = optimize });

    const build_options = b.addOptions();
    build_options.addOption(bool, "testfn", b.option(bool, "testfn", "Register test function") orelse false);
    pgzx.addOptions("build_options", build_options);

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
    b.getInstallStep().dependOn(&ext.step);

    // Extension build for unit tests. Same as above, but with testfn for sure true.
    const test_options = b.addOptions();
    test_options.addOption(bool, "testfn", true);
    pgzx.addOptions("build_options", test_options);
    const test_ext = pgbuild.addInstallExtension(.{
        .name = name,
        .version = version,
        .root_source_file = .{
            .path = "src/main.zig",
        },
        .root_dir = ".",
    });
    test_ext.lib.root_module.addImport("pgzx", pgzx);

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
