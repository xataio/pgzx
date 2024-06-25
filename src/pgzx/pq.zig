const std = @import("std");

const pg = @import("pgzx_pgsys");

const intr = @import("interrupts.zig");
const elog = @import("elog.zig");
const err = @import("err.zig");

pub const conv = @import("pq/conv.zig");

pub const Error = error{
    ConnectionFailure,
    QueryFailure,
    OperationFailed,
    PGErrorStack,
    SendFailed,
    PostmasterDied,
    EmptyQueue,
};

pub const ConnParams = std.StringHashMap([]const u8);

pub const ConnStatus = pg.ConnStatusType;
pub const PollingStatus = pg.PostgresPollingStatusType;
pub const TransactionStatus = pg.PGTransactionStatusType;

// libpqsrv wrappers and extensions.
const pqsrv = struct {
    // custom waitevent types retrieved from shared memory.

    var wait_event_connect: u32 = 0;
    var wait_event_command: u32 = 0;

    pub fn connectAsync(conninfo: [:0]const u8) Error!*pg.PGconn {
        try err.wrap(pg.pqsrv_connect_prepare, .{});
        return connOrErr(pg.PQconnectStart(conninfo.ptr));
    }

    pub fn connect(conninfo: [:0]const u8) Error!*pg.PGconn {
        const maybeConn: ?*pg.PGconn = try err.wrap(pg.pqsrv_connect, .{ conninfo.ptr, try get_wait_event_connect() });
        return connOrErr(maybeConn);
    }

    pub fn connectParamsAsync(
        keys: [*]const [*c]const u8,
        values: [*c]const [*c]const u8,
        expand_dbname: c_int,
    ) Error!*pg.PGconn {
        try err.wrap(pg.pqsrv_connect_prepare, .{});
        return connOrErr(pg.PQconnectStartParams(keys, values, expand_dbname));
    }

    pub fn connectParams(
        keys: [*]const [*c]const u8,
        values: [*c]const [*c]const u8,
        expand_dbname: c_int,
    ) Error!*pg.PGconn {
        const maybeConn = try err.wrap(pg.pqsrv_connect_params, .{ keys, values, expand_dbname, try get_wait_event_connect() });
        return connOrErr(@ptrCast(maybeConn));
    }

    pub fn waitConnected(conn: *pg.PGconn) !void {
        try err.wrap(pg.pqsrv_wait_connected, .{ conn, try get_wait_event_connect() });
    }

    inline fn get_wait_event_connect() Error!u32 {
        return pg.PG_WAIT_EXTENSION;
        // if (wait_event_connect == 0) {
        //     wait_event_connect = try err.wrap(c.WaitEventExtensionNew, .{"pq_connect"});
        // }
        // return wait_event_connect;
    }

    inline fn get_wait_event_command() Error!u32 {
        return pg.PG_WAIT_EXTENSION;
        // if (wait_event_command == 0) {
        //     wait_event_command = try err.wrap(c.WaitEventExtensionNew, .{"pq_command"});
        // }
        // return wait_event_command;
    }

    fn connOrErr(maybe_conn: ?*pg.PGconn) Error!*pg.PGconn {
        if (maybe_conn) |conn| {
            return conn;
        }
        return error.ConnectionFailure;
    }
};

pub const Conn = struct {
    const Self = @This();

    conn: *pg.PGconn,
    allocator: std.mem.Allocator,

    const Options = struct {
        wait: bool = false,
        check: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, conn: *pg.PGconn) Self {
        return Self{ .conn = conn, .allocator = allocator };
    }

    pub fn connect(allocator: std.mem.Allocator, conninfo: [:0]const u8, options: Options) !Self {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const local_allocator = arena.allocator();

        const conninfoZ = try local_allocator.dupeZ(u8, conninfo);
        const connector = if (options.wait) &pqsrv.connect else &pqsrv.connectAsync;
        const conn = Self.init(allocator, try connector(conninfoZ));
        conn.checkConnSuccess(options) catch |e| {
            conn.finish();
            return e;
        };
        return conn;
    }

    pub fn connectParams(allocator: std.mem.Allocator, params: ConnParams, options: Options) !Self {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const local_allocator = arena.allocator();

        const c_params = try PGConnParams.init(local_allocator, params);
        const connector = if (options.wait) &pqsrv.connectParams else &pqsrv.connectParamsAsync;
        const conn = Self.init(allocator, try connector(c_params.keys, c_params.values, 0));
        conn.checkConnSuccess(options) catch |e| {
            conn.finish();
            return e;
        };
        return conn;
    }

    fn waitConnected(self: *const Self) !void {
        return pqsrv.waitConnected(self.conn);
    }

    inline fn checkConnSuccess(self: *const Self, options: Options) !void {
        if (!options.wait or !options.check) {
            return;
        }

        if (self.status() != pg.CONNECTION_OK) {
            if (self.errorMessage()) |msg| {
                std.log.err("Connection error: {s}", .{msg});
            }
            return error.ConnectionFailure;
        }
    }

    pub fn connectPoll(self: *const Self) PollingStatus {
        return pg.PQconnectPoll(self.conn);
    }

    pub fn reset(self: *const Self) bool {
        return pg.PQresetStart(self.conn) != 0;
    }

    pub fn resetWait(self: *const Self) !void {
        if (!self.reset()) {
            return error.OperationFailed;
        }
        try self.waitConnected();
    }

    pub fn resetPoll(self: *const Self) PollingStatus {
        return pg.PQresetPoll(self.conn);
    }

    pub fn setNonBlocking(self: *const Self, arg: bool) !void {
        const rs = pg.PQsetnonblocking(self.conn, if (arg) 1 else 0);
        if (rs < 0) {
            return error.OperationFailed;
        }
    }

    pub fn exec(self: *const Self, query: [:0]const u8) !Result {
        const rc = pg.PQsendQuery(self.conn, query);
        if (rc == 0) {
            pqError(@src(), self.conn) catch |e| return e;
            return Error.SendFailed;
        }
        const res = try self.getRawResultLast();
        return try Self.initExecResult(self.conn, res);
    }

    pub fn execCommand(self: *const Self, command: [:0]const u8, args: anytype) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const local_allocator = arena.allocator();

        var buffer = std.ArrayList(u8).init(local_allocator);
        var res = try self.execParams(
            command,
            try buildParams(local_allocator, &buffer, args),
        );
        res.deinit();
    }

    pub fn execParams(self: *const Self, command: [:0]const u8, params: PGQueryParams) !Result {
        const rc = pg.PQsendQueryParams(
            self.conn,
            command,
            @as(c_int, @intCast(params.values.len)),
            if (params.types) |t| t.ptr else null,
            params.values.ptr,
            if (params.lengths) |l| l.ptr else null,
            if (params.formats) |f| f.ptr else null,
            params.result_format,
        );
        if (rc == 0) {
            pqError(@src(), self.conn) catch |e| return e;
            return Error.SendFailed;
        }
        return try self.getResultLast();
    }

    pub fn getResultLast(self: *const Self) !Result {
        const res = try self.getRawResultLast();
        return try Self.initExecResult(self.conn, res);
    }

    fn initExecResult(conn: ?*pg.PGconn, pgres: ?*pg.PGresult) !Result {
        if (responseCodeFatal(pg.PQresultStatus(pgres))) {
            defer pg.PQclear(pgres);
            const raw_error = pg.PQresultErrorMessage(pgres);
            if (raw_error) |msg| {
                return elog.Error(@src(), "{s}", .{std.mem.span(msg)});
            }
            return error.QueryFailure;
        }
        if (pgres) |r| {
            var res = Result.init(r);
            errdefer res.deinit();
            if (res.isError()) {
                if (res.errorMessage()) |msg| {
                    return elog.Error(@src(), "{s}", .{msg});
                }
                return error.QueryFailure;
            }
            return res;
        } else {
            pqError(@src(), conn) catch |e| return e;
            return error.QueryFailure;
        }
    }

    pub fn sendCommand(self: *const Self, command: [:0]const u8, args: anytype) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const local_allocator = arena.allocator();

        var buffer = std.ArrayList(u8).init(local_allocator);
        try self.sendQueryParams(
            command,
            try buildParams(local_allocator, &buffer, args),
        );
    }

    /// Send a query with parameters. We assume that the values are encoded in
    /// text format.
    pub fn sendQueryParams(self: *const Self, query: [:0]const u8, params: PGQueryParams) !void {
        std.log.info("conn '{*}' sendQueryParams: {s}", .{ self.conn, query });

        const n = params.values.len;
        if (params.types) |t| {
            if (n != t.len) {
                @panic("number of types must match number of values");
            }
        }
        if (params.lengths) |l| {
            if (n != l.len) {
                @panic("number of lengths must match number of values");
            }
        }
        if (params.formats) |f| {
            if (n != f.len) {
                @panic("number of formats must match number of values");
            }
        }

        const rc = pg.PQsendQueryParams(
            self.conn,
            query,
            @intCast(n),
            if (params.types) |t| t.ptr else null,
            params.values.ptr,
            if (params.lengths) |l| l.ptr else null,
            if (params.formats) |f| f.ptr else null,
            params.result_format,
        );
        if (rc == 0) {
            pqError(@src(), self.conn) catch |e| return e;
            return Error.SendFailed;
        }
    }

    pub fn sendQuery(self: *const Self, query: []const u8) !void {
        const rc = pg.PQsendQuery(self.conn, query);
        if (rc == 0) {
            pqError(@src()) catch |e| return e;
            return Error.SendFailed;
        }
    }

    pub fn waitCommandComplete(self: *const Self) !void {
        const ok = try self.getCommandOk();
        if (!ok) {
            return Error.OperationFailed;
        }
    }

    pub fn waitLastCommandComplete(self: *const Self) !void {
        while (try self.tryGetCommandOk()) |ok| {
            if (!ok) {
                return Error.OperationFailed;
            }
        }
    }

    // Consumes the next result and returns true if the result was not null and
    // and the status is PGRES_COMMAND_OK.
    // The result struct is cleared right away.
    pub fn getCommandOk(self: *const Self) !bool {
        return if (try self.tryGetCommandOk()) |r| r else error.EmptyQueue;
    }

    pub fn tryGetCommandOk(self: *const Self) !?bool {
        while (true) {
            if (try self.getResult()) |r| {
                if (r.isError()) {
                    if (r.errorMessage()) |msg| {
                        elog.Warning(@src(), "libpq error message: {s}", .{msg});
                    }
                    return false;
                }
                if (r.status() == pg.PGRES_NONFATAL_ERROR) { // ignore NOTICE or WARNING
                    continue;
                }

                return switch (r.status()) {
                    pg.PGRES_COMMAND_OK,
                    pg.PGRES_TUPLES_OK,
                    pg.PGRES_SINGLE_TUPLE,
                    => true,
                    else => false,
                };
            } else {
                return null;
            }
        }
    }

    pub fn getResult(self: *const Self) !?Result {
        const res = try self.getRawResult();
        return if (res) |r| Result.init(r) else null;
    }

    pub fn getRawResult(self: *const Self) !?*pg.PGresult {
        try self.waitReady();
        return pg.PQgetResult(self.conn);
    }

    pub fn getRawResultLast(self: *const Self) !?*pg.PGresult {
        var last: ?*pg.PGresult = null;
        errdefer {
            if (last) |r| pg.PQclear(r);
        }

        while (true) {
            const res = try self.getRawResult();
            if (res == null) break;

            if (last) |r| pg.PQclear(r);
            last = res;

            const stopLoop = switch (pg.PQresultStatus(res)) {
                pg.PGRES_COPY_IN,
                pg.PGRES_COPY_OUT,
                pg.PGRES_COPY_BOTH,
                => true,
                else => false,
            };
            if (stopLoop) {
                break;
            }
        }
        return last;
    }

    // Flush pending messages in the send queue and wait for the socket to
    // receive a result that can be read in a non-blocking manner.
    //
    // `waitReady` handles signals and will return an error if the postmaster
    // or CheckForInterrupts indicates that we should shutdown.
    pub fn waitReady(self: *const Self) !void {
        try intr.CheckForInterrupts();
        while (true) {
            var wait_flag: c_int = 0;

            // In case the send queue is not empty we want to be woken up when
            // the socket is writable. This ensures that the loop can continue
            // sending pending messages that are still enqueued in memory only.
            const send_queue_empty = try self.flush();
            if (!send_queue_empty) {
                wait_flag = pg.WL_SOCKET_WRITEABLE;
            }

            try self.consumeInput();
            if (self.isBusy()) {
                wait_flag |= pg.WL_SOCKET_READABLE;
            }

            if (wait_flag == 0) {
                break;
            }

            const rc = pg.WaitLatchOrSocket(pg.MyLatch, wait_flag, self.socket(), 0, pg.PG_WAIT_EXTENSION);
            if (checkFlag(pg.WL_POSTMASTER_DEATH, rc)) {
                return Error.PostmasterDied;
            }
            if (checkFlag(pg.WL_LATCH_SET, rc)) {
                pg.ResetLatch(pg.MyLatch);
                try intr.CheckForInterrupts();
            }
        }
    }

    // Flush the send queue. Returns true if the all data has been sent or if the queue is empty.
    // Return false is the send queue is not send completely.
    pub fn flush(self: *const Self) !bool {
        const rc = pg.PQflush(self.conn);
        if (rc < 0) {
            pqError(@src(), self.conn) catch |e| return e;
            return error.OperationFailed;
        }
        return rc == 0;
    }

    pub fn consumeInput(self: *const Self) !void {
        const rc = pg.PQconsumeInput(self.conn);
        if (rc == 0) {
            pqError(@src(), self.conn) catch |e| return e;
            return error.OperationFailed;
        }
    }

    pub fn finish(self: *const Self) void {
        pg.pqsrv_disconnect(self.conn);
    }

    pub fn status(self: *const Self) ConnStatus {
        return pg.PQstatus(self.conn);
    }

    pub fn transactionStatus(self: *const Self) TransactionStatus {
        return pg.PQtransactionStatus(self.conn);
    }

    pub fn serverVersion(self: *const Self) c_int {
        return pg.PQserverVersion(self.conn);
    }

    pub fn errorMessage(self: *const Self) ?[:0]const u8 {
        if (pg.PQerrorMessage(self.conn)) |msg| {
            return std.mem.span(msg);
        }
        return null;
    }

    pub fn socket(self: *const Self) c_int {
        return pg.PQsocket(self.conn);
    }

    pub fn backendPID(self: *const Self) c_int {
        return pg.PQbackendPID(self.conn);
    }

    pub fn host(self: *const Self) [:0]const u8 {
        return std.mem.span(pg.PQhost(self.conn));
    }

    pub fn port(self: *const Self) [:0]const u8 {
        return std.mem.span(pg.PQport(self.conn));
    }

    pub fn dbname(self: *const Self) [:0]const u8 {
        return std.mem.span(pg.PQdb(self.conn));
    }

    pub fn isBusy(self: *const Self) bool {
        return pg.PQisBusy(self.conn) != 0;
    }
};

const PGConnParams = struct {
    keys: [*]const [*c]const u8,
    values: [*c]const [*c]const u8,
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, in: std.StringHashMap([]const u8)) !PGConnParams {
        const n = in.count();
        var keys = try alloc.alloc([*c]const u8, n + 1);
        var values = try alloc.alloc([*c]const u8, n + 1);

        var i: usize = 0;
        var it = in.iterator();
        while (it.next()) |entry| {
            keys[i] = try alloc.dupeZ(u8, entry.key_ptr.*);
            values[i] = try alloc.dupeZ(u8, entry.value_ptr.*);
            i += 1;
        }
        keys[i] = null;
        values[i] = null;

        return PGConnParams{ .keys = keys.ptr, .values = values.ptr, .allocator = alloc };
    }

    pub fn deinit(self: *PGConnParams) void {
        self.allocator.free(self.keys);
        self.allocator.free(self.values);
    }
};

pub const StartupStatus = enum {
    CONNECTING,
    CONNECTED,
    ERROR,
};

pub const PollStartState = struct {
    polltype: pg.PostgresPollingStatusType,
    status: StartupStatus = StartupStatus.CONNECTING,

    const Self = @This();

    pub fn new(conn: *const Conn) Self {
        var self: Self = undefined;
        self.init();
        _ = self.update(conn);
        return self;
    }

    pub fn init(self: *Self) void {
        self.* = .{ .polltype = 0 };
    }

    pub fn update(self: *Self, conn: *const Conn) bool {
        const pq_status = conn.status();
        var status_update = switch (pq_status) {
            pg.CONNECTION_OK => StartupStatus.CONNECTED,
            pg.CONNECTION_BAD => StartupStatus.ERROR,
            else => StartupStatus.CONNECTING,
        };

        if (status_update != StartupStatus.CONNECTING) {
            const changed = self.status != status_update;
            self.status = status_update;
            return changed;
        }

        // still connecting
        self.polltype = conn.connectPoll();
        status_update = switch (self.polltype) {
            pg.PGRES_POLLING_FAILED => StartupStatus.ERROR,
            pg.PGRES_POLLING_OK => StartupStatus.CONNECTED,
            else => StartupStatus.CONNECTING,
        };
        const changed = self.status != status_update;
        self.status = status_update;
        return changed;
    }

    pub fn getEventMask(self: *const Self) u32 {
        if (self.status == StartupStatus.CONNECTING) {
            return switch (self.polltype) {
                pg.PGRES_POLLING_READING => pg.WL_SOCKET_READABLE,
                else => pg.WL_SOCKET_WRITEABLE,
            };
        }
        return 0;
    }
};

fn responseCodeFatal(response_code: pg.ExecStatusType) bool {
    return switch (response_code) {
        pg.PGRES_COMMAND_OK => false,
        pg.PGRES_TUPLES_OK => false,
        pg.PGRES_SINGLE_TUPLE => false,
        pg.PGRES_NONFATAL_ERROR => false,
        else => response_code > 0,
    };
}

pub const PGQueryParams = struct {
    values: []const [*c]const u8,

    // Optional OID types of the values. Required for binary encodings.
    // In case of text encoding optional.
    types: ?[]const pg.Oid = null,

    // byte length per value in case values are binary encoded.
    lengths: ?[]const c_int = null,

    // Optional array to indicate the value encoding per value.
    // If null all values are encoded in text format. Only required in case
    // parameters use the binary encoding.
    formats: ?[]const c_int = null,

    // Encoding format postgres should respond with. 0 for text, 1 for binary.
    result_format: c_int = 0,
};

// Build a set of parameters from Zig values to be used with execParams and
// sendQueryParams variants.
//
// The values and types arrays are allocated in the given allocator.
//
// WARNING:
// Do not deallocate the buffer while the PGQueryParams is still in use.
// Values are encoded into the given buffer. The values array will hold
// pointers into the buffer for each value.
pub fn buildParams(
    allocator: std.mem.Allocator,
    buffer: *std.ArrayList(u8),
    args: anytype,
) !PGQueryParams {
    const argsType = @TypeOf(args);
    const argsInfo = @typeInfo(argsType);
    if (argsInfo != .Struct or !argsInfo.Struct.is_tuple) {
        return std.debug.panic("params must be a tuple");
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var local_allocator = arena.allocator();

    // The buffer might grow and pointers might get invalidated.
    // Let's collect the positions of the values in the buffer so we can
    // collect the pointers after the encoding buffer has been fully written.
    var value_indices = try local_allocator.alloc(i32, argsInfo.Struct.fields.len);

    const writer: std.ArrayList(u8).Writer = buffer.writer();
    var types = try allocator.alloc(pg.Oid, argsInfo.Struct.fields.len);

    inline for (argsInfo.Struct.fields, 0..) |field, idx| {
        const codec = conv.find(field.type);
        types[idx] = codec.OID;

        const initPos = buffer.items.len;
        try codec.write(writer, @field(args, field.name));
        const pos = buffer.items.len;
        if (initPos == pos) {
            value_indices[idx] = -1;
        } else {
            value_indices[idx] = @intCast(initPos);
        }
    }

    var values = try allocator.alloc([*c]const u8, value_indices.len);
    for (value_indices, 0..) |pos, idx| {
        if (pos == -1) {
            values[idx] = null;
        } else {
            values[idx] = buffer.items[@intCast(pos)..].ptr;
        }
    }

    return PGQueryParams{
        .types = types,
        .values = values,
    };
}

const Result = struct {
    result: *pg.PGresult,

    const Self = @This();

    fn init(result: *pg.PGresult) Self {
        return Result{ .result = result };
    }

    pub fn deinit(self: Self) void {
        pg.PQclear(self.result);
    }

    pub fn status(self: Self) pg.ExecStatusType {
        return pg.PQresultStatus(self.result);
    }

    pub fn isError(self: Self) bool {
        return switch (self.status()) {
            pg.PGRES_EMPTY_QUERY,
            pg.PGRES_COMMAND_OK,
            pg.PGRES_TUPLES_OK,
            pg.PGRES_COPY_OUT,
            pg.PGRES_COPY_IN,
            pg.PGRES_COPY_BOTH,
            pg.PGRES_SINGLE_TUPLE,
            pg.PGRES_NONFATAL_ERROR, // warning or notice, but no error
            => false,
            else => true,
        };
    }

    pub fn errorMessage(self: Self) ?[:0]const u8 {
        if (pg.PQresultErrorMessage(self.result)) |msg| {
            return std.mem.span(msg);
        }
        return null;
    }
};

fn checkFlag(comptime pattern: anytype, value: @TypeOf(pattern)) bool {
    return (value & pattern) == pattern;
}

fn pqError(src: std.builtin.SourceLocation, conn: ?*pg.PGconn) error{PGErrorStack}!void {
    const rawerr = pg.PQerrorMessage(conn);
    if (rawerr == null) {
        return;
    }

    return elog.Error(src, "{s}", .{std.mem.span(rawerr)});
}
