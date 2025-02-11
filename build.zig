const std = @import("std");

pub const Build = @import("src/pgzx/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var pgbuild = Build.create(b, .{
        .target = target,
        .optimize = optimize,
    });

    const steps = .{
        .docs = b.step("docs", "Generate documentation"),
        .serve_docs = b.step("serve_docs", "Docs HTTP server http://localhost:8080/#docs.pgzx"),

        // Unit tests installer target
        // Optionally build and install the extension, so we can hook up with t a debugger and run tests manually.
        .install_unit = b.step("install-unit", "Install unit tests extension (for manual testing)"),

        .unit = b.step("unit", "Run pgzx unit tests"),
    };

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

    // codegen
    // The codegen produces Zig files that are imported as modules by pgzx.
    const node_tags_src = blk: {
        const tool = b.addExecutable(.{
            .name = "gennodetags",
            .root_source_file = b.path("./tools/gennodetags/main.zig"),
            .target = b.graph.host,
            .link_libc = true,
        });
        tool.root_module.addIncludePath(.{ .cwd_relative = pgbuild.getIncludeServerDir() });
        tool.root_module.addIncludePath(.{ .cwd_relative = pgbuild.getIncludeDir() });

        const tool_step = b.addRunArtifact(tool);
        break :blk tool_step.addOutputFileArg("nodetags.zig");
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
        module.addAnonymousImport("gen_node_tags", .{
            .root_source_file = node_tags_src,
            .imports = &.{
                .{ .name = "pgzx_pgsys", .module = pgzx_pgsys },
            },
        });

        break :blk module;
    };

    // docs step
    {
        // Internal target to build the docs from the document. The generated
        // documentation is installed in the <prefix>/share/pgzx/doc folder.
        const obj = b.addObject(.{
            .name = "docs",
            .root_module = pgzx,
        });
        const install_docs = b.addInstallDirectory(.{
            .source_dir = obj.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "share/pgzx/docs",
        });
        steps.docs.dependOn(&install_docs.step);

        const del_docs = b.addSystemCommand(&[_][]const u8{
            "rm", "-fr", "./docs",
        });
        const copy_docs = b.addSystemCommand(&[_][]const u8{
            "cp", "-fr", "./zig-out/share/pgzx/docs", ".",
        });

        copy_docs.step.dependOn(&del_docs.step);
        copy_docs.step.dependOn(&install_docs.step);
        steps.docs.dependOn(&copy_docs.step);

        // Use python to serve the docs via http.
        const serve_docs = b.addSystemCommand(&[_][]const u8{
            "python3", "-m", "http.server", "8080", "--directory", "./docs",
        });
        serve_docs.step.dependOn(&copy_docs.step);
        steps.serve_docs.dependOn(&serve_docs.step);
    }

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
        tests.lib.root_module.addOptions("build_options", test_options);

        tests.lib.root_module.addIncludePath(b.path("./src/pgzx/c/include/"));

        tests.lib.root_module.addImport("pgzx_pgsys", pgzx_pgsys);
        tests.lib.root_module.addImport("pgzx", pgzx);
        tests.lib.root_module.addAnonymousImport("gen_node_tags", .{
            .root_source_file = node_tags_src,
            .imports = &.{
                .{ .name = "pgzx_pgsys", .module = pgzx_pgsys },
            },
        });

        steps.install_unit.dependOn(&tests.step);

        break :blk tests;
    };

    // Unit test runner
    {
        const psql_run_tests = pgbuild.addRunTests(.{
            .name = "pgzx_unit",
            .db_user = "postgres",
            .db_port = 5432,
        });

        psql_run_tests.step.dependOn(&test_ext.step);
        steps.unit.dependOn(&psql_run_tests.step);
    }
}
