const std = @import("std");

const pg = @import("pgzx_pgsys");

const err = @import("err.zig");
const mem = @import("mem.zig");

const SourceLocation = std.builtin.SourceLocation;

/// The api module mirrors the PostgreSQL error and logging reporting macros;
///
/// Depending on the error level Postgres might
/// kill the process, kill the cluster, do a longjmp or continue with
/// normal control flow.
///
/// When raising an `Error` via `ereport` and similar functions, Postgres will use a longjump.
///
/// We also provide alternative `NoJump` functions that will return a Zig error
/// if you don't want Postgres error handling to take control over the process
/// flow. This is especially useful when you want to properly cleanup resources using defer or errdefer.
///
/// # Safety:
///
/// When calling report, then Postgres will use a longjmp if the the ERROR level is used.
/// A `longjmp` WILL NOT UNWIND THE STACK properly. This means that any defer statements
/// will not be execute. Use a `NoJump` variant if you want to emit a proper Zig error. Before returning to Postgres
/// the error must be rethrown (see [pgRethrow]) or cleaned up (see [FlushErrorState]).
///
pub const api = struct {
    pub const Level = enum(c_int) {
        Debug5 = pg.DEBUG5,
        Debug4 = pg.DEBUG4,
        Debug3 = pg.DEBUG3,
        Debug2 = pg.DEBUG2,
        Debug1 = pg.DEBUG1,

        Log = pg.LOG,
        LogServerOnly = pg.LOG_SERVER_ONLY,

        Info = pg.INFO,
        Notice = pg.NOTICE,
        Warning = pg.WARNING,
        WarningClientOnly = pg.WARNING_CLIENT_ONLY,
        Error = pg.ERROR,
        Fatal = pg.FATAL,
        Panic = pg.PANIC,
    };

    pub const Field = enum(c_int) {
        SchemaName = pg.PG_DIAG_SCHEMA_NAME,
        TableName = pg.PG_DIAG_TABLE_NAME,
        ColumnName = pg.PG_DIAG_COLUMN_NAME,
        DataTypeName = pg.PG_DIAG_DATATYPE_NAME,
        ConstraintName = pg.PG_DIAG_CONSTRAINT_NAME,
    };

    pub inline fn ereport(src: SourceLocation, level: Level, opts: anytype) void {
        ereportDomain(src, level, null, opts);
    }

    pub inline fn ereportNoJump(src: SourceLocation, level: Level, opts: anytype) err.PGError!void {
        try ereportDomainNoJump(src, level, null, opts);
    }

    pub inline fn errsave(src: SourceLocation, context: ?*pg.Node, opts: anytype) void {
        errsaveDomain(src, context, null, opts);
    }

    pub inline fn errsaveNoJump(src: SourceLocation, context: ?*pg.Node, opts: anytype) err.PGError!void {
        try errsaveDomainNoJump(src, context, null, opts);
    }

    pub inline fn errsaveValue(comptime T: type, src: SourceLocation, context: ?*pg.Node, value: T, opts: anytype) T {
        errsave(src, context, opts);
        return value;
    }

    pub inline fn errsaveValueNoJump(comptime T: type, src: SourceLocation, context: ?*pg.Node, value: T, opts: anytype) err.PGError!T {
        try errsaveNoJump(src, context, opts);
        return value;
    }

    pub inline fn ereportDomain(src: SourceLocation, level: Level, domain: ?[:0]const u8, opts: anytype) void {
        if (errstart(level, domain)) {
            inline for (opts) |opt| opt.call();
            errfinish(src, .{ .allow_longjmp = true }) catch unreachable;
        }
    }

    pub inline fn ereportDomainNoJump(src: SourceLocation, level: Level, domain: ?[:0]const u8, opts: anytype) err.PGError!void {
        if (errstart(level, domain)) {
            inline for (opts) |opt| opt.call();
            try errfinish(src, .{ .allow_longjmp = false });
        }
    }

    pub inline fn errsaveDomain(src: SourceLocation, context: ?*pg.Node, domain: ?[:0]const u8, opts: anytype) void {
        if (errsave_start(context, domain)) {
            inline for (opts) |opt| opt.call();
            errsave_finish(src, context, .{ .allow_longjmp = true }) catch unreachable;
        }
    }

    pub inline fn errsaveDomainNoJump(src: SourceLocation, context: ?*pg.Node, domain: ?[:0]const u8, opts: anytype) err.PGError!void {
        if (errsave_start(context, domain)) {
            inline for (opts) |opt| opt.call();
            try errsave_finish(src, context, .{ .allow_longjmp = false });
        }
    }

    pub inline fn errsaveDomainValue(src: SourceLocation, context: ?*pg.Node, value: anytype, domain: ?[:0]const u8, opts: anytype) @TypeOf(value) {
        errsaveDomain(src, context, domain, opts);
        return value;
    }

    pub inline fn errsaveDomainValueNoJump(src: SourceLocation, context: ?*pg.Node, value: anytype, domain: ?[:0]const u8, opts: anytype) err.PGError!@TypeOf(value) {
        try errsaveDomainNoJump(src, context, domain, opts);
        return value;
    }

    pub inline fn errstart(level: Level, domain: ?[:0]const u8) bool {
        return pg.errstart(@intFromEnum(level), if (domain) |d| d.ptr else null);
    }

    /// Finalize the current error report and raise a Postgres error if the error level is `ERROR`.
    pub inline fn errfinish(src: SourceLocation, kargs: struct { allow_longjmp: bool }) err.PGError!void {
        if (kargs.allow_longjmp) {
            return pg.errfinish(src.file, @as(c_int, @intCast(src.line)), src.fn_name);
        }
        try err.wrap(pg.errfinish, .{ src.file, @as(c_int, @intCast(src.line)), src.fn_name });
    }

    pub inline fn errsave_start(context: ?*pg.Node, domain: ?[:0]const u8) bool {
        return pg.errsave_start(context, if (domain) |d| d.ptr else null);
    }

    pub inline fn errsave_finish(src: SourceLocation, context: ?*pg.Node, kargs: struct { allow_longjmp: bool }) err.PGError!void {
        if (kargs.allow_longjmp) {
            pg.errsave_finish(context, src.file, @as(c_int, @intCast(src.line)), src.fn_name);
        }
        try err.wrap(pg.errsave_finish, .{ context, src.file, @as(c_int, @intCast(src.line)), src.fn_name });
    }

    const OptErrCode = struct {
        code: c_int,
        pub inline fn call(self: OptErrCode) void {
            _ = pg.errcode(self.code);
        }
    };

    /// Set the error code for the current error report.
    pub inline fn errcode(comptime sqlerrcode: c_int) OptErrCode {
        return OptErrCode{ .code = sqlerrcode };
    }

    fn FmtMessage(comptime msgtype: anytype, comptime fmt: []const u8, comptime Args: type) type {
        return struct {
            args: Args,

            pub inline fn call(self: @This()) void {
                var memctx = mem.getErrorContextThrowOOM();

                //@compileLog("FmtMessage:", fmt, self.args);

                const msg = std.fmt.allocPrintZ(memctx.allocator(), fmt, self.args) catch unreachable();
                _ = msgtype(msg.ptr);
            }
        };
    }

    pub inline fn errmsg(comptime fmt: []const u8, args: anytype) FmtMessage(pg.errmsg, fmt, @TypeOf(args)) {
        return .{ .args = args };
    }

    pub inline fn errdetail(comptime fmt: []const u8, args: anytype) FmtMessage(pg.errdetail, fmt, @TypeOf(args)) {
        return .{ .args = args };
    }

    pub inline fn errdetail_log(comptime fmt: []const u8, args: anytype) FmtMessage(pg.errdetail_log, fmt, @TypeOf(args)) {
        return .{ .args = args };
    }

    pub inline fn errhint(comptime fmt: []const u8, args: anytype) FmtMessage(pg.errhint, fmt, @TypeOf(args)) {
        return .{ .args = args };
    }

    const SpecialErrCode = enum {
        ForFileAccess,
        ForSocketAccess,

        pub inline fn call(self: SpecialErrCode) void {
            switch (self) {
                SpecialErrCode.ForFileAccess => pg.errcode_for_file_access(),
                SpecialErrCode.ForSocketAccess => pg.errcode_for_socket_access(),
            }
        }
    };

    pub inline fn errcodeForFile() SpecialErrCode {
        return SpecialErrCode.ForFileAccess;
    }

    pub inline fn errcodeForSocket() SpecialErrCode {
        return SpecialErrCode.ForSocketAccess;
    }

    const OptBacktrace = struct {
        pub inline fn call(self: OptBacktrace) void {
            _ = self;
            pg.errbacktrace();
        }
    };

    pub inline fn errbacktrace() OptBacktrace {
        return .{};
    }

    pub const OptHideStatement = struct {
        hide: bool = true,
        pub inline fn call(self: OptHideStatement) void {
            _ = pg.errhidestmt(self.hide);
        }
    };

    pub inline fn errhidestmt(hide: bool) OptHideStatement {
        return .{ .hide = hide };
    }

    pub const OptHideContext = struct {
        hide: bool = true,
        pub inline fn call(self: OptHideContext) void {
            _ = pg.errhidecontext(self.hide);
        }
    };

    pub inline fn errhidecontext(hide: bool) OptHideContext {
        return .{ .hide = hide };
    }

    pub const OptField = struct {
        field: Field,
        value: [:0]const u8,

        pub inline fn call(self: OptField) void {
            _ = pg.err_generic_string(@intFromEnum(self.field), self.value);
        }
    };

    pub inline fn errfield(field: Field, value: [:0]const u8) OptField {
        return OptField{ .field = field, .value = value };
    }

    pub inline fn errschema(name: [:0]const u8) OptField {
        return errfield(Field.SchemaName, name);
    }

    pub inline fn errtable(name: [:0]const u8) OptField {
        return errfield(Field.TableName, name);
    }

    pub inline fn errcolumn(name: [:0]const u8) OptField {
        return errfield(Field.ColumnName, name);
    }

    pub inline fn errdatatype(name: [:0]const u8) OptField {
        return errfield(Field.DataTypeName, name);
    }

    pub inline fn errconstraint(name: [:0]const u8) OptField {
        return errfield(Field.ConstraintName, name);
    }
};

pub usingnamespace api;

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
        errset.OutOfMemory => api.ereport(src, .Error, .{
            api.errcode(pg.ERRCODE_OUT_OF_MEMORY),
            api.errmsg("Not enough memory", .{}),
        }),
        else => |leftover_err| {
            api.ereport(src, .Error, .{
                api.errcode(pg.ERRCODE_INTERNAL_ERROR),
                api.errmsg("Unexpected error: {s}", .{@errorName(leftover_err)}),
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
    postgresLogFnLeven: c_int = pg.LOG_SERVER_ONLY,
} = .{};

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_prefix = @tagName(scope) ++ " ";
    const prefix = "Internal [" ++ comptime level.asText() ++ "] " ++ scope_prefix;

    if (!api.errstart(@enumFromInt(options.postgresLogFnLeven), null)) {
        return;
    }
    api.errcode(pg.ERRCODE_INTERNAL_ERROR).call();

    // We nede a temporary buffer for writing. Postgres will copy the message, so we should
    // clean up the buffer ourselvesi.
    var buf = std.ArrayList(u8).initCapacity(mem.PGCurrentContextAllocator, prefix.len + format.len + 1) catch return;
    defer buf.deinit();
    buf.writer().print(prefix, .{}) catch return;
    buf.writer().print(format, args) catch return;
    buf.append(0) catch return;
    _ = pg.errmsg("%s", buf.items[0 .. buf.items.len - 1 :0].ptr);

    const src = std.mem.zeroInit(SourceLocation, .{});
    api.errfinish(src, .{ .allow_longjmp = false }) catch {};
}

/// Use PostgreSQL elog to log a formatted message using the `DEBUG5` level.
pub fn Debug5(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.DEBUG5, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message using the `DEBUG4` level.
pub fn Debug4(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.DEBUG4, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message using the `DEBUG3` level.
pub fn Debug3(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.DEBUG3, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message using the `DEBUG2` level.
pub fn Debug2(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.DEBUG2, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message using the `DEBUG1` level.
pub fn Debug1(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.DEBUG1, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message using the `LOG` level.
///
/// Messages using `LOG` are send to the server by default.
pub fn Log(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.LOG, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message using the `LOG` level.
///
/// Append the error name to the error message or emit the top message from the
/// error stack if cause == PGErrorStack.
pub fn LogWithCause(src: SourceLocation, cause: anyerror, comptime fmt: []const u8, args: anytype) void {
    sendElogWithCause(src, pg.LOG, cause, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message using the `LOG` level.
///
/// Similar to `Log`, but message is never send to clients.
pub fn LogServerOnly(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.LOG_SERVER_ONLY, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message using the `LOG` level.
///
/// Similar to `LogWithCause`, but message is never send to clients.
///
/// Append the error name to the error message or emit the top message from the
/// error stack if cause == PGErrorStack.
pub fn LogServerOnlyWithCause(src: SourceLocation, cause: anyerror, comptime fmt: []const u8, args: anytype) void {
    sendElogWithCause(src, pg.LOG_SERVER_ONLY, cause, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Info` level.
pub fn Info(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.INFO, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Info` level.
///
/// Append the error name to the error message or emit the top message from the
/// error stack if cause == PGErrorStack.
pub fn InfoWithCause(src: SourceLocation, cause: anyerror, comptime fmt: []const u8, args: anytype) void {
    sendElogWithCause(src, pg.INFO, cause, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Notice` level.
pub fn Notice(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.NOTICE, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Notice` level.
///
/// Append the error name to the error message or emit the top message from the
/// error stack if cause == PGErrorStack.
pub fn NoticeWithCause(src: SourceLocation, cause: anyerror, comptime fmt: []const u8, args: anytype) void {
    sendElogWithCause(src, pg.NOTICE, cause, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Warning` level.
pub fn Warning(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.WARNING, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Warning` level.
///
/// Append the error name to the error message or emit the top message from the
/// error stack if cause == PGErrorStack.
pub fn WarningWithCause(src: SourceLocation, cause: anyerror, comptime fmt: []const u8, args: anytype) void {
    sendElogWithCause(src, pg.WARNING, cause, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `PGWARNING` level.
pub fn PGWarning(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.PGWARNING, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `PGWARNING` level.
///
/// Append the error name to the error message or emit the top message from the
/// error stack if cause == PGErrorStack.
pub fn PGWarningWithCause(src: SourceLocation, cause: anyerror, comptime fmt: []const u8, args: anytype) void {
    sendElogWithCause(src, pg.PGWARNING, cause, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Error` level.
///
/// Warning:
/// Using Error will cause Postgres to throw an error by using `longjump`.
pub fn ErrorThrow(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.ERROR, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Error` level.
///
/// Append the error name to the error message or emit the top message from the
/// error stack if cause == PGErrorStack.
///
/// Warning:
/// Using Error will cause Postgres to throw an error by using `longjump`.
pub fn ErrorThrowWithCause(src: SourceLocation, cause: anyerror, comptime fmt: []const u8, args: anytype) void {
    sendElogWithCause(src, pg.ERROR, cause, fmt, args);
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
        sendElog(src, pg.ERROR, fmt, args);
        unreachable;
    } else {
        return error.PGErrorStack;
    }
}

/// Use PostgreSQL elog to log a formatted message at `Error` level.
///
/// Append the error name to the error message or emit the top message from the
/// error stack if cause == PGErrorStack.
pub fn ErrorWithCause(src: SourceLocation, cause: anyerror, comptime fmt: []const u8, args: anytype) error{PGErrorStack} {
    var errctx = err.Context.init();
    defer errctx.pg_try_end();
    if (errctx.pg_try()) {
        sendElogWithCause(src, pg.ERROR, cause, fmt, args);
        unreachable;
    } else {
        return error.PGErrorStack;
    }
}

/// Use PostgreSQL elog to log a formatted message at `Fatal` level.
/// This will cause Postgres to kill the current process.
pub fn Fatal(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.FATAL, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `Fatal` level.
/// This will cause Postgres to kill the current process.o
///
/// Append the error name to the error message or emit the top message from the
/// error stack if cause == PGErrorStack.
pub fn FatalWithCause(src: SourceLocation, cause: anyerror, comptime fmt: []const u8, args: anytype) void {
    sendElogWithCause(src, pg.FATAL, cause, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `PANIC` level.
///
/// This will cause Postgres to stop the cluster.
pub fn Panic(src: SourceLocation, comptime fmt: []const u8, args: anytype) void {
    sendElog(src, pg.PANIC, fmt, args);
}

/// Use PostgreSQL elog to log a formatted message at `PANIC` level.
///
/// Append the error name to the error message or emit the top message from the
/// error stack if cause == PGErrorStack.
///
/// This will cause Postgres to stop the cluster.
pub fn PanicWithCause(src: SourceLocation, cause: anyerror, comptime fmt: []const u8, args: anytype) void {
    sendElogWithCause(src, pg.PANIC, cause, fmt, args);
}

pub fn emitIfPGError(e: anyerror) bool {
    if (e == error.PGErrorStack) {
        pg.EmitErrorReport();
        return true;
    }
    return false;
}

fn sendElog(src: SourceLocation, comptime level: c_int, comptime fmt: []const u8, args: anytype) void {
    api.ereport(src, @enumFromInt(level), .{
        api.errmsg(fmt, args),
    });
}

fn sendElogWithCause(src: SourceLocation, comptime level: c_int, cause: anyerror, comptime fmt: []const u8, args: anytype) void {
    if (emitIfPGError(cause)) {
        sendElog(src, level, fmt, args);
        return;
    }

    if (!api.errstart(@enumFromInt(level), null)) {
        return;
    }

    const err_name = @errorName(cause);

    var memctx = mem.getErrorContextThrowOOM();
    var buf = std.ArrayList(u8).initCapacity(memctx.allocator(), fmt.len + err_name.len + 20) catch unreachable;
    buf.writer().print(fmt, args) catch unreachable;
    buf.writer().writeAll(": ") catch unreachable;
    buf.writer().writeAll(err_name) catch unreachable;
    buf.writer().writeByte(0) catch unreachable;

    _ = pg.errmsg("%s", buf.items[0 .. buf.items.len - 1 :0].ptr);

    api.errfinish(src, .{ .allow_longjmp = true }) catch unreachable;
}
