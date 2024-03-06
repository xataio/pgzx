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

    // Reusable modules
    const pgzx = blk: {
        const module = b.addModule("pgzx", .{
            .root_source_file = .{ .path = "./src/pgzx.zig" },
            .target = target,
            .optimize = optimize,
        });
        module.addIncludePath(.{
            .path = "./src/pgzx/c/include/",
        });
        module.addIncludePath(.{
            .cwd_relative = pgbuild.getIncludeServerDir(),
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
        module.addIncludePath(.{
            .cwd_relative = pgbuild.getIncludeDir(),
        });
        module.addLibraryPath(.{
            .cwd_relative = pgbuild.getLibDir(),
        });
        module.linkSystemLibrary("pq", .{});

        break :blk module;
    };

    // Unit test extension
    {
        const psql_run_tests = pgbuild.addRunTests(.{
            .name = "pgzx_unit",
            .db_user = "postgres",
            .db_port = 5432,
        });

        const test_options = b.addOptions();
        test_options.addOption(bool, "testfn", true);

        const test_ext = pgbuild.addInstallExtension(.{
            .name = "pgzx_unit",
            .version = .{ .major = 0, .minor = 1 },
            .root_source_file = .{
                .path = "src/testing.zig",
            },
            .root_dir = "src/testing",
        });
        test_ext.lib.root_module.addIncludePath(.{
            .path = b.pathFromRoot("./src/pgzx/c/include/"),
        });
        test_ext.lib.root_module.addImport("pgzx", pgzx);
        test_ext.lib.root_module.addOptions("build_options", test_options);

        psql_run_tests.step.dependOn(&test_ext.step);

        var unit = b.step("unit", "Run pgzx unit tests");
        unit.dependOn(&psql_run_tests.step);
    }
}
