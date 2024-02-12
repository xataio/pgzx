const std = @import("std");

const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;

std_build: *std.Build,
paths: Paths,
target: std.Build.ResolvedTarget,
optimize: std.builtin.Mode,

const Build = @This();

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
        const PGIncludeServerDir: LazyPath = .{
            .cwd_relative = b.getIncludeServerDir(),
        };

        const root_dir = options.root_dir orelse
            b.std_build.pathJoin(&[_][]const u8{ "src/", options.name });

        const lib = blk: {
            const lib = b.std_build.addSharedLibrary(.{
                .name = options.name,
                .version = .{
                    .major = options.version.major,
                    .minor = options.version.minor,
                    .patch = 0,
                },
                .root_source_file = resolveLazyPath(b, root_dir, options.root_source_file, "main.zig"),
                .target = options.target orelse b.target,
                .optimize = options.optimize orelse b.optimize,
                .link_libc = options.link_libc,
            });
            lib.addIncludePath(PGIncludeServerDir);
            lib.linker_allow_shlib_undefined = options.link_allow_shlib_undefined;
            break :blk lib;
        };

        const extension_dir = b.addInstallExtensionDir(
            resolvePath(b, root_dir, options.extension_dir, "extension") orelse @panic("root_dir or extension_dir"),
        );

        var step = Step.init(.{
            .id = .custom,
            .name = "install extension",
            .owner = b.std_build,
        });
        step.dependOn(&b.addInstallExtensionLibArtifact(lib, options.name).step);
        step.dependOn(&extension_dir.step);

        const self = b.std_build.allocator.create(InstallExtension) catch @panic("OOM");
        self.* = .{
            .lib = lib,
            .step = step,
            .extension_dir = extension_dir,
        };
        return self;
    }

    fn resolveLazyPath(b: *Build, root_dir: []const u8, p: ?LazyPath, comptime default: []const u8) ?LazyPath {
        if (p) |configured_path| {
            return configured_path;
        }
        if (resolvePath(b, root_dir, null, default)) |path| {
            return .{
                .path = path,
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
};

const Run = struct {
    owner: *Build,
    argv: std.ArrayList([]const u8),
    step: Step,

    pub const base_id: Step.Id = .run;

    fn create(b: *Build, name: []const u8, argv: []const []const u8) *Run {
        var self = b.std_build.allocator.create(Run) catch @panic("OOM");
        self.* = .{
            .owner = b,
            .argv = std.ArrayList([]const u8).init(b.std_build.allocator),
            .step = Step.init(.{
                .id = base_id,
                .name = name,
                .owner = b.std_build,
                .makeFn = make,
            }),
        };
        self.argv.appendSlice(argv) catch @panic("OOM");
        return self;
    }

    fn addArg(self: *Run, arg: []const u8) void {
        self.argv.append(arg) catch @panic("OOM");
    }

    fn addArgOption(self: *Run, option: []const u8, arg: []const u8) void {
        self.addArg(option);
        self.addArg(arg);
    }

    fn addArgs(self: *Run, args: []const []const u8) void {
        for (args) |arg| {
            self.addArg(arg);
        }
    }

    fn hasSideEffects(self: Run) bool {
        _ = self;
        return true;
    }

    fn make(step: *Step, prog_node: *std.Progress.Node) !void {
        _ = prog_node;
        const self = @fieldParentPtr(Run, "step", step);
        const b = self.owner.std_build;

        var child = std.process.Child.init(self.argv.items, b.allocator);
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
            return step.fail("pg_regress failed. Exit code: {d}\n", .{exit_code});
        }
    }
};

pub const RunRegress = struct {
    pub const Options = struct {
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

    pub fn create(b: *Build, options: Options) *Run {
        const pg_regress_tool = b.getPGRegressPath();
        const root_dir = options.root_dir;
        var runner = Run.create(b, "pg_regress", &[_][]const u8{
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
};

pub const SharedLibraryExtension = struct {};

pub const InitOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
};

pub fn create(b: *std.Build, options: InitOptions) *Build {
    const self = b.allocator.create(Build) catch @panic("OOM");
    self.* = .{
        .std_build = b,
        .paths = .{},
        .target = options.target,
        .optimize = options.optimize,
    };
    return self;
}

pub fn getIncludeDir(self: *Build) []const u8 {
    return self.getPath(&self.paths.include_dir, "--includedir", false);
}

pub fn getIncludeServerDir(self: *Build) []const u8 {
    return self.getPath(&self.paths.include_server_dir, "--includedir-server", false);
}

pub fn getPackageLibDir(self: *Build) []const u8 {
    return self.getPath(&self.paths.package_lib_dir, "--pkglibdir", false);
}

pub fn getLibDir(self: *Build) []const u8 {
    return self.getPath(&self.paths.lib_dir, "--libdir", false);
}
pub fn getSharedDir(self: *Build) []const u8 {
    return self.getPath(&self.paths.shared_dir, "--sharedir", true);
}

pub fn getBinDir(self: *Build) []const u8 {
    return self.getPath(&self.paths.shared_dir, "--bindir", true);
}

pub fn getExtensionDir(self: *Build) []const u8 {
    self.paths.extension_dir = self.paths.extension_dir orelse blk: {
        const shared = self.getSharedDir();
        // break :blk self.std_build.pathJoin(shared, "extension");
        break :blk self.std_build.pathJoin(&[_][]const u8{ shared, "extension" });
    };
    return self.paths.extension_dir.?;
}

pub fn getPGRegressPath(self: *Build) []const u8 {
    self.paths.pg_regress_path = self.paths.pg_regress_path orelse blk: {
        const pkglib = self.getPackageLibDir();
        const pg_regress = "pgxs/src/test/regress/pg_regress";
        break :blk self.std_build.pathJoin(&[_][]const u8{ pkglib, pg_regress });
    };
    return self.paths.pg_regress_path.?;
}

pub fn installSharedLibExtension(self: *Build, artifact: *Step.Compile, ext_path: []const u8) void {
    self.std_build.getInstallStep().dependOn(&self.std_build.addInstallArtifact(artifact, .{
        .dest_dir = .{
            .override = .{
                .custom = self.std_build.pathJoin(&[_][]const u8{
                    self.getLibDir(),
                    ext_path,
                }),
            },
        },
    }).step);
}

pub fn addInstallExtension(self: *Build, options: InstallExtension.Options) *InstallExtension {
    return InstallExtension.create(self, options);
}

pub fn installExtension(self: *Build, options: InstallExtension.Options) void {
    self.std_build.getInstallStep().dependOn(&self.addInstallExtension(options).step);
}

pub fn installExtensionLibArtifact(self: *Build, artifact: *Step.Compile, name: []const u8) void {
    self.std_build.getInstallStep().dependOn(&self.addInstallExtensionLibArtifact(artifact, name).step);
}

pub fn addInstallExtensionLibArtifact(self: *Build, artifact: *Step.Compile, name: []const u8) *Step.InstallFile {
    const lib_suffix = artifact.rootModuleTarget().dynamicLibSuffix();
    const plugin_name = std.fmt.allocPrint(self.std_build.allocator, "{s}{s}", .{ name, lib_suffix }) catch @panic("OOM");
    return self.std_build.addInstallFileWithDir(
        artifact.getEmittedBin(),
        .{
            .custom = self.makeRelPath(self.getPackageLibDir()),
        },
        plugin_name,
    );
}

pub fn addInstallExtensionDir(self: *Build, source_dir: []const u8) *Step.InstallDir {
    return self.std_build.addInstallDirectory(.{
        .source_dir = .{
            .path = source_dir,
        },
        .install_dir = .{
            .custom = "",
        },
        .install_subdir = self.getExtensionDir(),
    });
}

pub fn installExtensionDir(self: *Build, source_dir: []const u8) void {
    self.std_build.getInstallStep().dependOn(&self.addInstallExtensionDir(source_dir).step);
}

pub fn addRegress(self: *Build, options: RunRegress.Options) *Run {
    return RunRegress.create(self, options);
}

fn getPath(self: *Build, path: *?[]const u8, question: []const u8, relative: bool) []const u8 {
    path.* = path.* orelse blk: {
        var p = self.runPGConfig(question);
        if (relative) {
            p = self.makeRelPath(p);
        }
        break :blk p;
    };
    return path.*.?;
}

fn makeRelPath(self: *Build, path: []const u8) []const u8 {
    const cwd = self.getPGHome();
    return std.fs.path.relative(self.std_build.allocator, cwd, path) catch @panic("failed to make relative path");
}

pub fn runPGConfig(self: *Build, question: []const u8) []const u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const argv = [_][]const u8{
        findPGConfig(),
        question,
    };

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

    // Copy the result onto the builders allocator
    return self.std_build.dupe(path);
}

pub fn getPGHome(self: *Build) []const u8 {
    self.paths.pg_home = self.paths.pg_home orelse blk: {
        if (std.os.getenv("PG_HOME")) |path| {
            break :blk path;
        }

        const bindir = self.getBinDir();
        break :blk std.fs.path.dirname(bindir);
    };
    return self.paths.pg_home.?;
}

fn findPGConfig() []const u8 {
    return getenvOr("PG_CONFIG", "pg_config");
}

fn getenvOr(name: []const u8, default: []const u8) []const u8 {
    return std.os.getenv(name) orelse default;
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
