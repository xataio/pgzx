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
    const build_docs = b.addSystemCommand(&[_][]const u8{ "zig", "test", "src/pgzx.zig", "-femit-docs", "-fno-emit-bin" });
    const docs = b.step("docs", "Generate documentation");
    docs.dependOn(&build_docs.step);

    // Reusable modules
    const pgzx = b.addModule("pgzx", .{
        .root_source_file = .{ .path = "./src/pgzx.zig" },
        .target = target,
        .optimize = optimize,
    });
    pgzx.addIncludePath(.{
        .path = "./src/pgzx/c/include/",
    });
    pgzx.addIncludePath(.{
        .cwd_relative = pgbuild.getIncludeServerDir(),
    });
    // libpq support
    pgzx.addCSourceFiles(.{
        .files = &[_][]const u8{
            b.pathFromRoot("./src/pgzx/c/libpqsrv.c"),
        },
        .flags = &[_][]const u8{
            "-I", pgbuild.getIncludeDir(),
            "-I", pgbuild.getIncludeServerDir(),
        },
    });
    pgzx.addIncludePath(.{
        .cwd_relative = pgbuild.getIncludeDir(),
    });
    pgzx.addLibraryPath(.{
        .cwd_relative = pgbuild.getLibDir(),
    });
    pgzx.linkSystemLibrary("pq", .{});
}
