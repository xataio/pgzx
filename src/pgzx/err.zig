const std = @import("std");

const pg = @import("pgzx_pgsys");

const mem = @import("mem.zig");

pub const PGError = error{
    // error from calling a postgres function. The actual error message
    // is stored on the postgres errordata stack.
    PGErrorStack,

    // Background worker errors
    SignalFlagAlreadyConfigured,
    FailStartBackgroundWorker,
    WorkerNotRunning,
    PostmasterDied,

    // Datum value conversion errors
    NotEnoughArguments,
    UnexpectedNullValue,
    StringLengthMismatch,

    // SPI
    SPIError,
    SPIConnectFailed,
    SPIUnconnected,
    SPINoAttribute,
    SPIArgument,
    SPICopy,
    SPITransaction,
    SPIOpUnknown,
    SPIInvalidRowIndex,

    // Signaling
    OperationCanceled,
};

pub const ElogIndicator = error{
    PGErrorStack,
};

/// Rethrow a postgres error.
/// Do not use PG_RE_THROW directly. Use `pg_re_throw` instead to ensure
/// that the PostgreSQL error handlers find the correct error state and
/// memory context it would expect.
pub fn pgRethrow() callconv(.C) void {
    // Postgres error handling does set the active memory context to the
    // ErrorContext when calling longjmp.
    // Because we did restore the memory context we want to make sure that we
    // set it back to ErrorContext before we rethrow the error
    _ = pg.MemoryContextSwitchTo(pg.ErrorContext);
    pg.PG_RE_THROW();
}

/// Capture the postgres error context when calling into postgres functions.
/// Postgres uses setjmp and longjmp to handle errors. This might cause
/// problems for defer and errdefer statements in zig code.
///
/// In Postgres one uses PG_TRY, PG_CATCH, PG_FINALLY, and PG_END_TRY to capture errors
/// to ensure that functions can cleanup before they re-throw the error.
///
/// Use PGErrorContext.capture() and pg_try_end to capture the error context.
/// Use `if (err_context.pg_try()) { ... }` to start a try block. `pg_try` will
/// return false if the enclosed code did throw a Postgres ERROR.
///
/// Postgres error handling does set the active memory context to the ErrorContext.
/// For this reason we also capture the MemoryContext and pg_try_end it at then end.
///
/// Postgres stores the error message in the `errordata` variable, which holds
/// a limit stack of error messages. Use `ignore_err()` if you don't want to
/// bubble up the error to Postgres later on. `ignore_err()` will clean up the
/// errordata stack in case an error was thrown. Otherwise `ignore_err()` will
/// do nothing.
///
/// Example: rethrow
/// Capture error and "rethrow" as normal zig error. Postgres error stack still exists
/// and we should rethrow the error before returning to postgres via `pgRethrow`.
/// By converting the error to a zig error we ensure that defer and errdefer statements
/// in the call chain will be executed correctly.
///
///   result = {
///       var err_context = PGErrorContext.capture();
///       defer err_context.pg_try_end();
///       if (err_context.pg_try()) {
///           pg.<postgres function>(...);
///       } else {
///         return error.PGErrorStack;
///       }
///   }
///
/// Example: catch and ignore.
/// We catch the error and clean the postgres error stack. There will be no evidence
/// that something went wrong.
///
///   var err_context = PGErrorContext.capture();
///   defer err_context.pg_try_end();
///   if (err_context.pg_try()) {
///     return pg.<postgres function>(...);
///   } else {
///     c.pg.FlushErrorState();
///     return <default value>;
///   }
///
pub const Context = struct {
    exception_stack: [*c]pg.sigjmp_buf,
    context_stack: [*c]pg.ErrorContextCallback,
    memory_context: pg.MemoryContext,
    local_sigjump_buf: pg.sigjmp_buf,

    const Self = @This();
    pub fn init() Self {
        return .{
            .exception_stack = pg.PG_exception_stack,
            .context_stack = pg.error_context_stack,
            .memory_context = pg.CurrentMemoryContext,
            .local_sigjump_buf = undefined,
        };
    }

    /// Install the local error context with Postgres and return `true`.
    /// In case Postgres throws an error, `pg_try` will return `false`.
    ///
    /// IMPORTANT:
    /// - `pg_try_end` must be used to properly cleanup the error handler stack.
    ///
    /// WARNING:
    /// NEVER RENMOVE THE 'inline'. `sigsetjmp` will will not work correctly if used
    /// within a function as we do here. By forcing the function to be inline
    /// the `sigsetjmp` happens correctly within the stack context of the caller.
    pub inline fn pg_try(self: *Self) bool {
        if (pg.sigsetjmp(&self.local_sigjump_buf, 0) == 0) {
            pg.PG_exception_stack = &self.local_sigjump_buf;
            return true;
        } else {
            return false;
        }
    }

    /// Restore the error context to the state before `pg_try` was called.
    pub fn deinit(self: *Self) void {
        self.pg_try_end();
    }

    /// Restore the error context to the state before `pg_try` was called.
    pub fn pg_try_end(self: *Self) void {
        pg.PG_exception_stack = self.exception_stack;
        pg.error_context_stack = self.context_stack;
        _ = pg.MemoryContextSwitchTo(self.memory_context);
    }

    /// Error handler to ignore the postgres error.
    /// The error stack with pending error messages will be cleaned up.
    pub fn ignore_err(self: *Self) void {
        _ = self;
        pg.FlushErrorState();
    }

    /// Turn a postgres longjmp based error into a zig error.
    pub fn errorValue(self: *Self) error{PGErrorStack} {
        _ = self;
        return error.PGErrorStack;
    }

    /// Rethrow the error as a Postgres error including the longjmp.
    ///
    /// This will call deinit automatically before rethrowing the error.
    pub fn rethrow(self: *Self) noreturn {
        self.deinit();
        pgRethrow();
        unreachable;
    }
};

pub inline fn wrap(comptime f: anytype, args: anytype) ElogIndicator!wrap_ret(@TypeOf(f)) {
    var errctx = Context.init();
    defer errctx.deinit();
    if (errctx.pg_try()) {
        return @call(.auto, f, args);
    } else {
        return errctx.errorValue();
    }
}

inline fn wrap_ret(comptime f: type) type {
    const ti = @typeInfo(f);
    if (ti != .@"fn") {
        @compileError("wrap only works with functions");
    }
    return ti.@"fn".return_type.?;
}
