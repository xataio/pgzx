const std = @import("std");

const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;

const Build = @This();

std_build: *std.Build,
paths: Paths,
options: struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
},
debug: DebugOptions,

modules: struct {
    builder: *Build = undefined,

    const Self = @This();

    fn loadModule(mods: Self, name: []const u8) *std.Build.Module {
        const dep = mods.builder.std_build.dependency("pgzx", mods.builder.options);
        return dep.module(name);
    }

    pub fn pgzx(mods: Self) *std.Build.Module {
        return mods.loadModule("pgzx");
    }

    pub fn pgsys(mods: Self) *std.Build.Module {
        return mods.loadModule("pgsys");
    }
},

// We use project to collect common build optoins and resources.
//
// When creating the docs or build and install steps, `Compile` step is
// directly configured to emit these kind of resources. Because we do not
// always want to emit everything we are forced to create separate `Compile`
// step instances for the different commands we want to run. The `Project`
// struct helps us to create properly configured resources, including
// dependencies.
//
pub const Project = struct {
    pgbuild: *Build,
    build: *std.Build,
    deps: struct {
        pgzx: *std.Build.Module,
    },
    options: std.StringArrayHashMapUnmanaged(*Step.Options),
    config: Config,

    pub const Config = struct {
        name: []const u8,
        version: ExtensionVersion,

        root_dir: []const u8,
        root_source_file: ?[]const u8 = null,

        extension_dir: ?[]const u8 = null,
    };

    pub fn init(b: *std.Build, c: Config) Project {
        const pgbuild = Build.create(b, .{
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
            .debug = .{
                .pg_config = false,
                .extension_lib = false,
            },
        });

        var proj_config = c;
        if (c.root_source_file == null) {
            const file_name = std.fmt.allocPrint(b.allocator, "{s}.zig", .{c.name}) catch unreachable;
            const src: []u8 = std.fs.path.join(b.allocator, &[_][]const u8{ c.root_dir, file_name }) catch unreachable;
            proj_config.root_source_file = src;
        }
        if (c.extension_dir == null) {
            proj_config.extension_dir = "./extension/";
        }

        return Project{
            .build = b,
            .pgbuild = pgbuild,
            .deps = .{
                .pgzx = pgbuild.modules.pgzx(),
            },
            .config = proj_config,
            .options = std.StringArrayHashMapUnmanaged(*Step.Options).init(b.allocator, &.{}, &.{}) catch unreachable,
        };
    }

    pub fn extensionLib(proj: Project) *Step.Compile {
        const lib = proj.pgbuild.addExtensionLib(.{
            .name = proj.config.name,
            .version = proj.config.version,
            .root_dir = proj.config.root_dir,
            .root_source_file = proj.build.path(proj.config.root_source_file.?),
        });
        lib.root_module.addImport("pgzx", proj.deps.pgzx);

        var it = proj.options.iterator();
        while (it.next()) |kv| {
            lib.root_module.addOptions(kv.key_ptr.*, kv.value_ptr.*);
        }

        return lib;
    }

    pub fn installExtensionLib(proj: Project) *Step.InstallFile {
        return proj.pgbuild.addInstallExtensionLibArtifact(proj.extensionLib(), proj.config.name);
    }

    pub fn installExtensionDir(proj: Project) *Step.InstallDir {
        return proj.pgbuild.addInstallExtensionDir(proj.config.extension_dir.?);
    }

    pub fn addOptions(proj: *Project, module_name: []const u8, options: *Step.Options) void {
        proj.options.put(proj.build.allocator, module_name, options) catch unreachable;
    }
};

pub const DebugOptions = struct {
    pg_config: bool = false,
    extension_dir: bool = false,
    extension_lib: bool = false,
};

const Paths = struct {
    cwd: ?[]const u8 = null,
    bin_dir: ?[]const u8 = null,
    lib_dir: ?[]const u8 = null,
    pg_home: ?[]const u8 = null,
    include_dir: ?[]const u8 = null,
    include_server_dir: ?[]const u8 = null,
    package_lib_dir: ?[]const u8 = null,
    shared_dir: ?[]const u8 = null,
    extension_dir: ?[]const u8 = null,
    pg_regress_path: ?[]const u8 = null,
    psql_path: ?[]const u8 = null,
};

pub const ExtensionVersion = struct {
    major: u32,
    minor: u32,
};

pub const InstallExtension = struct {
    lib: *Step.Compile,
    extension_dir: *Step.InstallDir,
    step: Step,

    pub const Options = struct {
        // plugin opts
        name: []const u8,
        version: ExtensionVersion,

        // paths
        root_dir: ?[]const u8 = null,
        root_source_file: ?LazyPath = null,
        extension_dir: ?[]const u8 = null,

        // shared library options
        target: ?std.Build.ResolvedTarget = null,
        optimize: ?std.builtin.Mode = null,
        single_threaded: bool = true,
        link_libc: bool = true,
        link_allow_shlib_undefined: bool = true,
    };

    pub fn create(b: *Build, options: Options) *InstallExtension {
        const root_dir = options.root_dir orelse
            b.std_build.pathJoin(&[_][]const u8{ "src/", options.name });

        const lib = b.addExtensionLib(.{
            .name = options.name,
            .version = options.version,
            .root_dir = root_dir,
            .root_source_file = options.root_source_file,
            .link_libc = options.link_libc,
        });

        const extension_dir = b.addInstallExtensionDir(
            resolvePath(b, root_dir, options.extension_dir, "extension") orelse @panic("root_dir or extension_dir"),
        );

        const install_ext = b.std_build.allocator.create(InstallExtension) catch @panic("OOM");
        install_ext.* = .{
            .lib = lib,
            .step = b.joinSteps("install_extension", .{
                &b.addInstallExtensionLibArtifact(lib, options.name).step,
                &extension_dir.step,
            }),
            .extension_dir = extension_dir,
        };
        return install_ext;
    }
};

pub const RunExec = struct {
    owner: *Build,
    argv: std.ArrayList([]const u8),
    step: Step,

    pub const base_id: Step.Id = .run;

    fn create(b: *Build, name: []const u8, argv: []const []const u8) *RunExec {
        var r = b.std_build.allocator.create(RunExec) catch @panic("OOM");
        r.* = .{
            .owner = b,
            .argv = std.ArrayList([]const u8).init(b.std_build.allocator),
            .step = Step.init(.{
                .id = base_id,
                .name = name,
                .owner = b.std_build,
                .makeFn = make,
            }),
        };
        r.argv.appendSlice(argv) catch @panic("OOM");
        return r;
    }

    fn addArg(r: *RunExec, arg: []const u8) void {
        r.argv.append(arg) catch @panic("OOM");
    }

    fn addArgOption(r: *RunExec, option: []const u8, arg: []const u8) void {
        r.addArg(option);
        r.addArg(arg);
    }

    fn addArgs(r: *RunExec, args: []const []const u8) void {
        for (args) |arg| {
            r.addArg(arg);
        }
    }

    fn hasSideEffects(r: RunExec) bool {
        _ = r;
        return true;
    }

    fn make(step: *Step, options: Step.MakeOptions) anyerror!void {
        _ = options;

        const r: *RunExec = @fieldParentPtr("step", step);
        const b = r.owner.std_build;

        var child = std.process.Child.init(r.argv.items, b.allocator);
        child.cwd = b.build_root.path;
        child.cwd_dir = b.build_root.handle;
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        const term = child.spawnAndWait() catch @panic("failed to start process");
        const exit_code = switch (term) {
            .Exited => |code| code,
            else => @panic("process failed"),
        };
        if (exit_code != 0) {
            return step.fail("{s} failed. Exit code: {d}\n", .{ r.step.name, exit_code });
        }
    }
};

pub const InitOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    debug: DebugOptions = .{},
};

pub fn create(std_build: *std.Build, options: InitOptions) *Build {
    const b = std_build.allocator.create(Build) catch @panic("OOM");
    b.* = .{
        .std_build = std_build,
        .paths = .{},
        .options = .{
            .target = options.target,
            .optimize = options.optimize,
        },
        .debug = options.debug,
        .modules = .{},
    };
    b.*.modules.builder = b;
    return b;
}

pub fn getIncludeDir(b: *Build) []const u8 {
    return b.getPath(&b.paths.include_dir, "--includedir", false);
}

pub fn getIncludeServerDir(b: *Build) []const u8 {
    return b.getPath(&b.paths.include_server_dir, "--includedir-server", false);
}

pub fn getPackageLibDir(b: *Build) []const u8 {
    return b.getPath(&b.paths.package_lib_dir, "--pkglibdir", false);
}

pub fn getLibDir(b: *Build) []const u8 {
    return b.getPath(&b.paths.lib_dir, "--libdir", false);
}
pub fn getSharedDir(b: *Build) []const u8 {
    return b.getPath(&b.paths.shared_dir, "--sharedir", true);
}

pub fn getBinDir(b: *Build) []const u8 {
    return b.getPath(&b.paths.bin_dir, "--bindir", false);
}

pub fn getExtensionDir(b: *Build) []const u8 {
    b.paths.extension_dir = b.paths.extension_dir orelse blk: {
        const shared = b.getSharedDir();
        break :blk b.std_build.pathJoin(&[_][]const u8{ shared, "extension" });
    };
    return b.paths.extension_dir.?;
}

pub fn getPGRegressPath(b: *Build) []const u8 {
    b.paths.pg_regress_path = b.paths.pg_regress_path orelse blk: {
        const pkglib = b.getPackageLibDir();
        const pg_regress = "pgxs/src/test/regress/pg_regress";
        break :blk b.std_build.pathJoin(&[_][]const u8{ pkglib, pg_regress });
    };
    return b.paths.pg_regress_path.?;
}

pub fn getPsqlPath(b: *Build) []const u8 {
    b.paths.psql_path = b.paths.psql_path orelse blk: {
        const bin_dir = b.getBinDir();
        break :blk b.std_build.pathJoin(&[_][]const u8{ bin_dir, "psql" });
    };
    return b.paths.psql_path.?;
}

const ExtensionLibOptions = struct {
    name: []const u8,
    version: ExtensionVersion,
    root_dir: ?[]const u8 = null,
    root_source_file: ?LazyPath = null,
    link_libc: bool = true,
};

pub fn addExtensionLib(b: *Build, options: ExtensionLibOptions) *Step.Compile {
    const root_dir = options.root_dir orelse
        b.std_build.pathJoin(&[_][]const u8{ "src/", options.name });

    const lib = b.std_build.addSharedLibrary(.{
        .name = options.name,
        .version = .{
            .major = options.version.major,
            .minor = options.version.minor,
            .patch = 0,
        },
        .root_source_file = b.resolveLazyPath(root_dir, options.root_source_file, "main.zig"),
        .target = b.options.target,
        .optimize = b.options.optimize,
        .link_libc = options.link_libc,
    });
    lib.addIncludePath(.{
        .cwd_relative = b.getIncludeServerDir(),
    });
    lib.linker_allow_shlib_undefined = true;
    return lib;
}

pub fn installSharedLibExtension(b: *Build, artifact: *Step.Compile, ext_path: []const u8) void {
    b.std_build.getInstallStep().dependOn(&b.std_build.addInstallArtifact(artifact, .{
        .dest_dir = .{
            .override = .{
                .custom = b.std_build.pathJoin(&[_][]const u8{
                    b.getLibDir(),
                    ext_path,
                }),
            },
        },
    }).step);
}

pub fn addInstallExtension(b: *Build, options: InstallExtension.Options) *InstallExtension {
    return InstallExtension.create(b, options);
}

pub fn installExtension(b: *Build, options: InstallExtension.Options) *InstallExtension {
    const ext = b.addInstallExtension(options);
    b.std_build.getInstallStep().dependOn(&ext.step);
    return ext;
}

pub fn installExtensionLibArtifact(b: *Build, artifact: *Step.Compile, name: []const u8) *Step.InstallFile {
    const file_artifact = b.addInstallExtensionLibArtifact(artifact, name);
    b.std_build.getInstallStep().dependOn(&file_artifact.step);
    return file_artifact;
}

pub fn addInstallExtensionLibArtifact(b: *Build, artifact: *Step.Compile, name: []const u8) *Step.InstallFile {
    const lib_suffix = artifact.rootModuleTarget().dynamicLibSuffix();
    const plugin_name = std.fmt.allocPrint(b.std_build.allocator, "{s}{s}", .{ name, lib_suffix }) catch @panic("OOM");

    // TODO: resolve paths to ensures they are canonicalized.

    // Normally it is expected that the package libdir is a subdirectory of the pg_home.
    // Unfortunately in Nix the path can be reconfigured using an environment
    // variable, in which case the libdir is no subfolder of the Postgres
    // installation.
    //
    // If that is the case we only copy the shared library to the libdir if the
    // installation prefix is indeed the local postgres installation path.
    // Otherwise we force the shared library to be copied to the prefix path
    // directly (no sub folders).
    const pg_home = b.getPGHome();
    const package_lib_dir = b.getPackageLibDir();
    const is_deploy = std.mem.eql(u8, b.std_build.install_prefix, pg_home);
    const target_lib_dir = if (is_deploy or std.mem.startsWith(u8, package_lib_dir, pg_home))
        b.makeRelPath(package_lib_dir)
    else
        ".";

    const artifact_file = artifact.getEmittedBin();
    if (b.debug.extension_lib) {
        std.debug.print("pg_home: {s}\n", .{b.getPGHome()});
        std.debug.print("Package lib dir: {s}\n", .{package_lib_dir});

        std.debug.print("Configure step: install extension lib: {s} -> {s}/{s}\n", .{
            artifact_file.getDisplayName(),
            target_lib_dir,
            plugin_name,
        });
    }

    return b.std_build.addInstallFileWithDir(
        artifact_file,
        .{ .custom = target_lib_dir },
        plugin_name,
    );
}

pub fn addInstallExtensionDir(b: *Build, source_dir: []const u8) *Step.InstallDir {
    const source_dir_path = b.std_build.path(source_dir);
    const ext_dir = b.getExtensionDir();

    if (b.debug.extension_dir) {
        std.debug.print("Configure step: install extension dir: {s} -> {s}\n", .{ source_dir, ext_dir });
    }

    return b.std_build.addInstallDirectory(.{
        .source_dir = source_dir_path,
        .install_dir = .prefix,
        .install_subdir = ext_dir,
    });
}

pub fn installExtensionDir(b: *Build, source_dir: []const u8) void {
    b.std_build.getInstallStep().dependOn(&b.addInstallExtensionDir(source_dir).step);
}

pub const PGRegressOptions = struct {
    scripts: []const []const u8,
    root_dir: []const u8,

    db_user: ?[]const u8 = null,
    db_host: ?[]const u8 = null,
    db_port: ?u16 = null,
    db_name: ?[]const u8 = null,
    debug: bool = false,
    create_role: ?[]const u8 = null,
    load_extensions: ?[]const []const u8 = null,
};

pub fn addRegress(b: *Build, options: PGRegressOptions) *RunExec {
    const pg_regress_tool = b.getPGRegressPath();
    const root_dir = options.root_dir;
    var runner = RunExec.create(b, "pg_regress", &[_][]const u8{
        pg_regress_tool,
        "--inputdir",
        root_dir,
        "--outputdir",
        root_dir,
        "--expecteddir",
        root_dir,
    });

    if (options.db_host) |db_host| {
        runner.addArgs(&[_][]const u8{ "--host", db_host });
    }
    if (options.db_port) |db_port| {
        runner.addArgs(&[_][]const u8{
            "--port",
            std.fmt.allocPrint(b.std_build.allocator, "{d}", .{db_port}) catch @panic("OOM"),
        });
    }
    if (options.db_user) |db_user| {
        runner.addArgs(&[_][]const u8{ "--user", db_user });
    }
    if (options.db_name) |db_name| {
        runner.addArgs(&[_][]const u8{ "--dbname", db_name });
    }
    if (options.create_role) |create_role| {
        runner.addArgs(&[_][]const u8{ "--create-role", create_role });
    }
    if (options.debug) {
        runner.addArgs(&[_][]const u8{"--debug"});
    }
    if (options.load_extensions) |list| {
        for (list) |ext| {
            runner.addArgs(&[_][]const u8{ "--load-extension", ext });
        }
    }

    runner.addArgs(options.scripts);
    return runner;
}

pub const RunTestsOptions = struct {
    name: []const u8,

    db_user: ?[]const u8 = null,
    db_host: ?[]const u8 = null,
    db_port: ?u16 = null,
    db_name: ?[]const u8 = null,
};

/// This runs the following SQL commands:
///
///  DROP FUNCTION IF EXISTS run_tests;
///  CREATE FUNCTION run_tests() RETURNS INTEGER AS '\''$libdir/{name}'\'' LANGUAGE C IMMUTABLE;
///  SELECT run_tests();
pub fn addRunTests(b: *Build, options: RunTestsOptions) *RunExec {
    const sql = std.fmt.allocPrint(
        b.std_build.allocator,
        \\ DROP FUNCTION IF EXISTS run_tests;
        \\ CREATE FUNCTION run_tests() RETURNS INTEGER AS '$libdir/{s}' LANGUAGE C IMMUTABLE;
        \\ SELECT run_tests();
    ,
        .{options.name},
    ) catch @panic("OOM");
    const psql_exe = b.getPsqlPath();
    var runner = RunExec.create(b, "run_tests_psql", &[_][]const u8{
        psql_exe,
        "-c",
        sql,
    });

    if (options.db_host) |db_host| {
        runner.addArgs(&[_][]const u8{ "--host", db_host });
    }
    if (options.db_port) |db_port| {
        runner.addArgs(&[_][]const u8{
            "--port",
            std.fmt.allocPrint(b.std_build.allocator, "{d}", .{db_port}) catch @panic("OOM"),
        });
    }
    if (options.db_user) |db_user| {
        runner.addArgs(&[_][]const u8{ "--user", db_user });
    }
    if (options.db_name) |db_name| {
        runner.addArgs(&[_][]const u8{ "--dbname", db_name });
    }
    return runner;
}

fn getPath(b: *Build, path: *?[]const u8, question: []const u8, relative: bool) []const u8 {
    path.* = path.* orelse blk: {
        var p = b.runPGConfig(question);
        if (relative) {
            p = b.makeRelPath(p);
        }
        break :blk p;
    };
    return path.*.?;
}

fn makeRelPath(b: *Build, path: []const u8) []const u8 {
    const cwd = b.getPGHome();
    return std.fs.path.relative(b.std_build.allocator, cwd, path) catch @panic("failed to make relative path");
}

pub fn runPGConfig(b: *Build, question: []const u8) []const u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const argv = [_][]const u8{
        findPGConfig(),
        question,
    };

    if (b.debug.pg_config) {
        std.debug.print("Running pg_config: {s}\n", .{argv});
    }

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    var stdout = std.ArrayList(u8).init(allocator);
    var stderr = std.ArrayList(u8).init(allocator);

    child.spawn() catch @panic("failed to start pg_config");
    child.collectOutput(&stdout, &stderr, 1024) catch @panic("error while reading from pg_config");
    const term = child.wait() catch @panic("awaiting pg_config exit");
    if (!check_exec(term)) {
        @panic("pg_config failed");
    }

    const path = trimWhitespace(stdout.items);
    if (path.len == 0) {
        @panic("pg_config failed");
    }

    if (b.debug.pg_config) {
        std.debug.print("pg_config returned: {s}\n", .{path});
    }

    // Copy the result onto the builders allocator
    return b.std_build.dupe(path);
}

pub fn getPGHome(b: *Build) []const u8 {
    b.paths.pg_home = b.paths.pg_home orelse blk: {
        const bindir = b.getBinDir();
        break :blk std.fs.path.dirname(bindir);
    };
    return b.paths.pg_home.?;
}

fn findPGConfig() []const u8 {
    return getenvOr("PG_CONFIG", "pg_config");
}

fn getenvOr(name: []const u8, default: []const u8) []const u8 {
    return std.posix.getenv(name) orelse default;
}

fn check_exec(term: anytype) bool {
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn trimWhitespace(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and std.ascii.isWhitespace(s[start])) : (start += 1) {}

    var end: usize = s.len;
    while (end > start and std.ascii.isWhitespace(s[end - 1])) : (end -= 1) {}

    return s[start..end];
}

fn resolveLazyPath(b: *Build, root_dir: []const u8, p: ?LazyPath, comptime default: []const u8) ?LazyPath {
    if (p) |configured_path| {
        return configured_path;
    }
    if (resolvePath(b, root_dir, null, default)) |path| {
        return .{
            .cwd_relative = path,
        };
    }
    return null;
}

fn resolvePath(b: *Build, root_dir: []const u8, p: ?[]const u8, default: []const u8) ?[]const u8 {
    if (p) |configured_path| {
        return configured_path;
    }
    return b.std_build.pathJoin(&[_][]const u8{ root_dir, default });
}

inline fn joinSteps(b: *Build, name: []const u8, steps: anytype) Step {
    var step = Step.init(.{
        .id = .custom,
        .name = name,
        .owner = b.std_build,
    });
    inline for (steps) |s| {
        step.dependOn(s);
    }
    return step;
}
