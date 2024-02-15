const std = @import("std");
const err = @import("err.zig");
const mem = @import("mem.zig");
const c = @import("c.zig");

const SourceLocation = std.builtin.SourceLocation;

/// Turn the zig error into a postgres error. The errror will be send to
/// Postgres and logged using the error level.
///
/// This returns the internal PGError.PGErrorStack error, which indicates
/// that we have some error context on the Postgres error stack. Use
/// `pgRethrow` or `throwAsPostgresError` to properly throw the error.
pub fn intoPostgresError(src: SourceLocation, e: anyerror) err.PGError!void {
    return try err.wrap(throwAsPostgresError, .{ src, e });
}

/// Turn the error into a postgres error and throw it directly.
/// Postgres will use a longjmp to pass the error up the call stack.
///
/// Use `intoPostgresError` if you don't want Postgres to take control yet.
pub fn throwAsPostgresError(src: SourceLocation, e: anyerror) noreturn {
    const errset = error{
        PGErrorStack,
        OutOfMemory,
    };

    switch (e) {
        errset.PGErrorStack => err.pgRethrow(),
        errset.OutOfMemory => Report.init(src, c.ERROR).pgRaise(.{
            .code = c.ERRCODE_OUT_OF_MEMORY,
            .message = "Not enough memory",
        }),
        else => |leftover_err| {
            const unexpected = "Unexpeced error";

            var buf: [1024]u8 = undefined;
            const msg = std.fmt.bufPrintZ(buf[0..], "Unexpected error: {s}", .{@errorName(leftover_err)}) catch unexpected;
            Report.init(src, c.ERROR).pgRaise(.{
                .code = c.ERRCODE_INTERNAL_ERROR,
                .message = msg,
            });
        },
    }

    unreachable;
}

/// This function returns true if the error is PGError.PGErrorStack.
pub fn isPostgresError(e: anyerror) bool {
    return e == error.PGErrorStack;
}

/// Provide support to integrate std.log with Postgres elog.
pub var options: struct {
    postgresLogFnLeven: c_int = c.LOG_SERVER_ONLY,
} = .{};

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_prefix = @tagName(scope) ++ " ";
    const prefix = "Internal [" ++ comptime level.asText() ++ "] " ++ scope_prefix;

    // We nede a temporary buffer for writing. Postgres will copy the message, so we should
    // clean up the buffer ourselvesi.
    var buf = std.ArrayList(u8).initCapacity(mem.PGCurrentContextAllocator, prefix.len + format.len + 1) catch return;
    defer buf.deinit();
    buf.writer().print(prefix, .{}) catch return;
    buf.writer().print(format, args) catch return;
    buf.append(0) catch return;

    const src = std.mem.zeroInit(SourceLocation, .{});
    Report.init(src, options.postgresLogFnLeven).raise(.{
        .code = c.ERRCODE_INTERNAL_ERROR,
        .message = buf.items[0 .. buf.items.len - 1 :0],
    }) catch {};
}

/// Use PostgreSQL elog to log a formatted message using the `LOG` level.
///
/// Messages using `LOG` are send to the server by default.
pub fn Log(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, c.LOG, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message using the `LOG` level.
///
/// Similar to `Log`, but message is never send to clients.
pub fn LogServerOnly(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, c.LOG_SERVER_ONLY, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Info` level.
pub fn Info(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, c.INFO, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Notice` level.
pub fn Notice(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, c.NOTICE, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Warning` level.
pub fn Warning(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, c.WARNING, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `PGWARNING` level.
pub fn PGWarning(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, c.PGWARNING, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Error` level.
///
/// Warning:
/// Using Error will cause Postgres to throw an error by using `longjump`.
pub fn ErrorThrow(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, c.ERROR, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Error` level.
///
/// We capture the error that Postgres would throw and return it as a Zig error.
/// The message is still on the Postgres error stack. Make sure to rethrow the
/// error via `pgRethrow` or have someone call FlushErrorState to cleanup the error stack.
pub fn Error(src: SourceLocation, comptime fmt: []const u8, args: anytype) error{PGErrorStack} {
    var errctx = err.Context.init();
    defer errctx.pg_try_end();
    if (errctx.pg_try()) {
        sendElog(src, c.ERROR, fmt, args);
        unreachable;
    } else {
        return error.PGErrorStack;
    }
}

/// Use PostgreSQL elog to log a formatted message at `Fatal` level.
/// This will cause Postgres to kill the current process.
pub fn Fatal(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, c.FATAL, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `PANIC` level.
///
/// This will cause Postgres to stop the cluster.
pub fn Panic(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, c.PANIC, fmt, args);
}

fn sendElog(src: SourceLocation, comptime level: c_int, comptime fmt: []const u8, args: anytype) void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    var memctx = mem.getErrorContextThrowOOM();
    const msg = std.fmt.allocPrintZ(memctx.allocator(), fmt, args) catch unreachable();
    Report.init(src, level).pgRaise(.{ .message = msg });
}

pub const Report = struct {
    src: std.builtin.SourceLocation,
    level: c_int,

    const Self = @This();

    pub fn init(src: SourceLocation, level: c_int) Self {
        return .{ .src = src, .level = level };
    }

    const Details = struct {
        code: ?c_int = null,
        message: ?[:0]const u8 = null,
    };

    /// Raises a postgres error report similat to `ereport` in C.
    /// But we capture the postgres longjmp and rethrow it as zig error.
    /// This allows you to properly cleanup resources.
    /// Use `pgRethrow` to give back control to PostgreSQL longjump based
    /// error handling.
    pub fn raise(self: Self, details: Details) error{PGErrorStack}!void {
        return try err.wrap(Self.pgRaise, .{ self, details });
    }

    /// Throw a postgres error. Depending on the error level Postgres might
    /// kill the process, kill the cluster, do a longjmp or continue with
    /// normal control flow. In code that uses pgRaise assume that
    /// Postgres will use longjmp and prepare your code to potentially capture the error
    /// to ensure cleanups.
    /// If you don't want Postgres error handling to take control better use `raise`.
    ///
    /// # Memory safety:
    ///
    /// Postgres error handling will copy all strings passed to pgRaise onto ErrorContext.
    /// When passing formatted strings make sure that no allocation can leak.
    /// For example by allocating into another MemoryContext that will be
    /// cleaned up by Postgres once the call is handled. Or a small buffer on the stack itself.
    ///
    /// # Callstack safety:
    ///
    /// When calling pgRaise, then Postgres will use a longjmp if the the ERROR level is used.
    /// A `longjmp` WILL NOT UNWIND THE STACK properly. This means that any defer statements
    /// will not be execute. Use [raise] if you want to emit a proper Zig error. Before returning to Postgres
    /// the error must be rethrown (see [pgRethrow]) or cleaned up (see [FlushErrorState]).
    pub fn pgRaise(self: Self, details: Details) void {
        var data = self.init_err_data(details);
        c.ThrowErrorData(&data);
    }

    inline fn init_err_data(self: Self, details: Details) c.ErrorData {
        return std.mem.zeroInit(c.ErrorData, .{
            .elevel = self.level,
            .sqlerrcode = details.code orelse 0,
            .message = if (details.message) |m| @constCast(m.ptr) else null,
            .hide_stmt = true,
            .hide_ctx = true,
            .filename = self.src.file,
            .lineno = @as(c_int, @intCast(self.src.line)),
            .funcname = self.src.fn_name,
            .assoc_context = c.CurrentMemoryContext,
        });
    }
};
