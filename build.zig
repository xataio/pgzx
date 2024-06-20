const std = @import("std");

pub const Build = @import("src/pgzx/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var pgbuild = Build.create(b, .{
        .target = target,
        .optimize = optimize,
    });

    // docs step
    {
        const build_docs = b.addSystemCommand(&[_][]const u8{ "zig", "test", "src/pgzx.zig", "-femit-docs", "-fno-emit-bin" });
        const docs = b.step("docs", "Generate documentation");
        docs.dependOn(&build_docs.step);
    }

    // pgzx_pgsys module: C bindings to Postgres
    const pgzx_pgsys = blk: {
        const module = b.addModule("pgzx_pgsys", .{
            .root_source_file = b.path("./src/pgzx/c.zig"),
            .target = target,
            .optimize = optimize,
        });

        // Internal C headers
        module.addIncludePath(b.path("./src/pgzx/c/include/"));

        // Postgres Headers
        module.addIncludePath(.{
            .cwd_relative = pgbuild.getIncludeServerDir(),
        });
        module.addIncludePath(.{
            .cwd_relative = pgbuild.getIncludeDir(),
        });
        module.addLibraryPath(.{
            .cwd_relative = pgbuild.getLibDir(),
        });

        // libpq support
        module.addCSourceFiles(.{
            .files = &[_][]const u8{
                "./src/pgzx/c/libpqsrv.c",
            },
            .flags = &[_][]const u8{
                "-I", pgbuild.getIncludeDir(),
                "-I", pgbuild.getIncludeServerDir(),
            },
        });
        module.linkSystemLibrary("pq", .{});

        break :blk module;
    };

    // pgzx: main project module.
    // This module re-exports pgzx_pgsys, other generated modules, and utility functions.
    const pgzx = blk: {
        const module = b.addModule("pgzx", .{
            .root_source_file = b.path("./src/pgzx.zig"),
            .target = target,
            .optimize = optimize,
        });
        module.addImport("pgzx_pgsys", pgzx_pgsys);

        break :blk module;
    };

    // Unit test extension
    const test_ext = blk: {
        const test_options = b.addOptions();
        test_options.addOption(bool, "testfn", true);

        const tests = pgbuild.addInstallExtension(.{
            .name = "pgzx_unit",
            .version = .{ .major = 0, .minor = 1 },
            .root_source_file = b.path("src/testing.zig"),
            .root_dir = "src/testing",
            .link_libc = true,
            .link_allow_shlib_undefined = true,
        });
        tests.lib.root_module.addIncludePath(b.path("./src/pgzx/c/include/"));
        tests.lib.root_module.addImport("pgzx", pgzx);
        tests.lib.root_module.addOptions("build_options", test_options);

        break :blk tests;
    };

    // Unit tests installer target
    // Optionally build and install the extension, so we can hook up with t a debugger and run tests manually.
    {
        var install_unit = b.step("install-unit", "Install unit tests extension (for manual testing)");
        install_unit.dependOn(&test_ext.step);
    }

    // Unit test runner
    {
        const psql_run_tests = pgbuild.addRunTests(.{
            .name = "pgzx_unit",
            .db_user = "postgres",
            .db_port = 5432,
        });

        psql_run_tests.step.dependOn(&test_ext.step);

        var unit = b.step("unit", "Run pgzx unit tests");
        unit.dependOn(&psql_run_tests.step);
    }
}
