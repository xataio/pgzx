const std = @import("std");

const c = @import("c.zig");
const intr = @import("interrupts.zig");
const elog = @import("elog.zig");

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

const err = @import("err.zig");

pub const ConnParams = std.StringHashMap([]const u8);

pub const ConnStatus = c.ConnStatusType;
pub const PollingStatus = c.PostgresPollingStatusType;
pub const TransactionStatus = c.PGTransactionStatusType;

// libpqsrv wrappers and extensions.
const pqsrv = struct {
    // custom waitevent types retrieved from shared memory.

    var wait_event_connect: u32 = 0;
    var wait_event_command: u32 = 0;

    pub fn connectAsync(conninfo: []const u8) Error!*c.PGconn {
        try err.wrap(c.pqsrv_connect_prepare, .{});
        return connOrErr(c.PQconnectStart(conninfo));
    }

    pub fn connect(conninfo: []const u8) Error!*c.PGconn {
        const maybeConn = try err.wrap(c.pqsrv_connect, .{ conninfo, try get_wait_event_connect() });
        return connOrErr(maybeConn);
    }

    pub fn connectParamsAsync(
        keys: [*]const [*c]const u8,
        values: [*c]const [*c]const u8,
        expand_dbname: c_int,
    ) Error!*c.PGconn {
        try err.wrap(c.pqsrv_connect_prepare, .{});
        return connOrErr(c.PQconnectStartParams(keys, values, expand_dbname));
    }

    pub fn connectParams(
        keys: [*]const [*c]const u8,
        values: [*c]const [*c]const u8,
        expand_dbname: c_int,
    ) Error!*c.PGconn {
        const maybeConn = try err.wrap(c.pqsrv_connect_params, .{ keys, values, expand_dbname, try get_wait_event_connect() });
        return connOrErr(@ptrCast(maybeConn));
    }

    inline fn get_wait_event_connect() Error!u32 {
        if (wait_event_connect == 0) {
            wait_event_connect = try err.wrap(c.WaitEventExtensionNew, .{"pq_connect"});
        }
        return wait_event_connect;
    }

    inline fn get_wait_event_command() Error!u32 {
        if (wait_event_command == 0) {
            wait_event_command = try err.wrap(c.WaitEventExtensionNew, .{"pq_command"});
        }
        return wait_event_command;
    }

    fn connOrErr(maybe_conn: ?*c.PGconn) Error!*c.PGconn {
        if (maybe_conn) |conn| {
            return conn;
        }
        return error.ConnectionFailure;
    }
};

pub const AsyncConn = struct {
    const Self = @This();
    pub usingnamespace ConnMixin(Self);

    conn: *c.PGconn,
    allocator: std.mem.Allocator,

    pub fn connect(allocator: std.mem.Allocator, conninfo: []const u8) !Self {
        return try Self.connectWith(pqsrv.connectAsync, allocator, conninfo);
    }

    pub fn connectParams(allocator: std.mem.Allocator, conn_params: ConnParams) !Self {
        return try Self.connectParamsWith(pqsrv.connectParamsAsync, allocator, conn_params);
    }

    pub fn connectPoll(self: *Self) PollingStatus {
        return c.PQconnectPoll(self.conn);
    }

    pub fn reset(self: *Self) bool {
        return c.PQresetStart(self.conn) != 0;
    }

    pub fn resetPoll(self: *Self) PollingStatus {
        return c.PQresetPoll(self.conn);
    }

    pub fn setNonBlocking(self: *Self, arg: bool) !void {
        const status = c.PQsetnonblocking(self.conn, if (arg) 1 else 0);
        if (status < 0) {
            return error.OperationFailed;
        }
    }

    pub fn asSync(self: *Self) !Conn {
        return Conn{
            .conn = self.conn,
            .allocator = self.allocator,
        };
    }

    pub fn sendCommand(self: *Self, command: []const u8, args: anytype) !void {
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
    pub fn sendQueryParams(self: *Self, query: [:0]const u8, params: PGQueryParams) !void {
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

        const rc = c.PQsendQueryParams(
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

    pub fn sendQuery(self: *Self, query: []const u8) !void {
        const rc = c.PQsendQuery(self.conn, query);
        if (rc == 0) {
            pqError(@src()) catch |e| return e;
            return Error.SendFailed;
        }
    }

    // Consumes the next result and returns true if the result was not null and
    // and the status is PGRES_COMMAND_OK.
    // The result struct is cleared right away.
    pub fn getCommandOk(self: *Self) !bool {
        while (true) {
            if (try self.getResult()) |r| {
                if (r.is_error()) {
                    return false;
                }
                if (r.status() == c.PGRES_NONFATAL_ERROR) { // ignore NOTICE or WARNING
                    continue;
                }

                return switch (r.status()) {
                    c.PGRES_COMMAND_OK,
                    c.PGRES_TUPLES_OK,
                    c.PGRES_SINGLE_TUPLE,
                    => true,
                    else => false,
                };
            } else {
                return Error.EmptyQueue;
            }
        }
    }

    pub fn getResult(self: *Self) !?Result {
        try self.waitReady();
        const res = c.PQgetResult(self.conn);
        return if (res) |r| Result.init(r) else null;
    }

    // Flush pending messages in the send queue and wait for the socket to
    // receive a result that can be read in a non-blocking manner.
    //
    // `waitReady` handles signals and will return an error if the postmaster
    // or CheckForInterrupts indicates that we should shutdown.
    pub fn waitReady(self: *Self) !void {
        try intr.CheckForInterrupts();
        while (true) {
            var wait_flag: c_int = 0;

            // In case the send queue is not empty we want to be woken up when
            // the socket is writable. This ensures that the loop can continue
            // sending pending messages that are still enqueued in memory only.
            const send_queue_empty = try self.flush();
            if (!send_queue_empty) {
                wait_flag = c.WL_SOCKET_WRITEABLE;
            }

            try self.consumeInput();
            if (self.isBusy()) {
                wait_flag |= c.WL_SOCKET_READABLE;
            }

            if (wait_flag == 0) {
                break;
            }

            const rc = c.WaitLatchOrSocket(c.MyLatch, wait_flag, self.socket(), 0, c.PG_WAIT_EXTENSION);
            if (checkFlag(c.WL_POSTMASTER_DEATH, rc)) {
                return Error.PostmasterDied;
            }
            if (checkFlag(c.WL_LATCH_SET, rc)) {
                c.ResetLatch(c.MyLatch);
                try intr.CheckForInterrupts();
            }
        }
    }

    // Flush the send queue. Returns true if the all data has been sent or if the queue is empty.
    // Return false is the send queue is not send completely.
    pub fn flush(self: *Self) !bool {
        const rc = c.PQflush(self.conn);
        if (rc < 0) {
            pqError(@src(), self.conn) catch |e| return e;
            return error.OperationFailed;
        }
        return rc == 0;
    }

    pub fn consumeInput(self: *Self) !void {
        const rc = c.PQconsumeInput(self.conn);
        if (rc == 0) {
            pqError(@src(), self.conn) catch |e| return e;
            return error.OperationFailed;
        }
    }

    pub fn isBusy(self: *Self) bool {
        return c.PQisBusy(self.conn) != 0;
    }
};

pub const Conn = struct {
    const Self = @This();
    pub usingnamespace ConnMixin(Self);

    conn: *c.PGconn,
    allocator: std.mem.Allocator,

    pub fn connect(allocator: std.mem.Allocator, conninfo: []const u8) !Self {
        return try Self.connectWith(c.libpqsrv_connect, allocator, conninfo);
    }

    pub fn connectCheck(allocator: std.mem.Allocator, conninfo: []const u8) !Self {
        var self = Self.connect(allocator, conninfo);
        self.checkConnSuccess() catch |e| {
            self.finish();
            return e;
        };
        return self;
    }

    pub fn connectParams(allocator: std.mem.Allocator, conn_params: ConnParams) !Self {
        return try Self.connectParamsWith(pqsrv.connectParams, allocator, conn_params);
    }

    pub fn connectParamsCheck(allocator: std.mem.Allocator, conn_params: ConnParams) !Self {
        var self = try Self.connectParams(allocator, conn_params);
        self.checkConnSuccess() catch |e| {
            self.finish();
            return e;
        };
        return self;
    }

    fn checkConnSuccess(self: *Self) !void {
        if (self.status() != c.CONNECTION_OK) {
            if (self.errorMessage()) |msg| {
                std.log.err("Connection error: {s}", .{msg});
            }
            return error.ConnectionFailure;
        }
    }

    pub fn reset(self: *Self) void {
        c.PQreset(self.conn);
    }

    pub fn asAsync(self: *Self) AsyncConn {
        return AsyncConn{
            .conn = self.conn,
            .allocator = self.allocator,
        };
    }

    pub fn exec(self: *Self, query: [:0]const u8) !Result {
        const res: ?*c.PGresult = @ptrCast(try err.wrap(
            c.pqsrv_exec,
            .{ self.conn, query, try pqsrv.get_wait_event_command() },
        ));
        return try Self.initExecResult(self.conn, res);
    }

    pub fn execCommand(self: *Self, command: [:0]const u8, args: anytype) !void {
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

    pub fn execParams(self: *Self, command: [:0]const u8, params: PGQueryParams) !Result {
        const res: ?*c.PGresult = @ptrCast(try err.wrap(c.pqsrv_exec_params, .{
            self.conn,
            command,
            @as(c_int, @intCast(params.values.len)),
            if (params.types) |t| t.ptr else null,
            params.values.ptr,
            if (params.lengths) |l| l.ptr else null,
            if (params.formats) |f| f.ptr else null,
            params.result_format,
            try pqsrv.get_wait_event_command(),
        }));
        return try Self.initExecResult(self.conn, res);
    }

    fn initExecResult(conn: ?*c.PGconn, pgres: ?*c.PGresult) !Result {
        if (responseCodeFatal(c.PQresultStatus(pgres))) {
            defer c.PQclear(pgres);
            const raw_error = c.PQresultErrorMessage(pgres);
            if (raw_error) |msg| {
                return elog.Error(@src(), "{s}", .{std.mem.span(msg)});
            }
            return error.QueryFailure;
        }
        if (pgres) |r| {
            var res = Result.init(r);
            errdefer res.deinit();
            if (res.is_error()) {
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
};

inline fn ConnMixin(comptime Self: type) type {
    return struct {
        fn connectWith(
            connector: anytype,
            allocator: std.mem.Allocator,
            conninfo: []const u8,
        ) !Self {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const local_allocator = arena.allocator();

            const conninfoZ = try local_allocator.dupeZ(u8, conninfo);
            const conn = try connector(conninfoZ);
            if (conn) |nc| {
                return Self{ .conn = nc, .allocator = allocator };
            }

            pqError(@src()) catch |e| return e;
            return error.ConnectionFailure;
        }

        fn connectParamsWith(
            comptime connector: fn ([*]const [*c]const u8, [*c]const [*c]const u8, c_int) Error!*c.PGconn,
            allocator: std.mem.Allocator,
            conn_params: std.StringHashMap([]const u8),
        ) !Self {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const local_allocator = arena.allocator();

            const c_params = try PGConnParams.init(local_allocator, conn_params);
            const conn = try connector(c_params.keys, c_params.values, 0);
            return Self{ .conn = conn, .allocator = allocator };
        }

        pub fn finish(self: *Self) void {
            c.pqsrv_disconnect(self.conn);
        }

        pub fn status(self: *Self) ConnStatus {
            return c.PQstatus(self.conn);
        }

        pub fn transactionStatus(self: *Self) TransactionStatus {
            return c.PQtransactionStatus(self.conn);
        }

        pub fn serverVersion(self: *Self) c_int {
            return c.PQserverVersion(self.conn);
        }

        pub fn errorMessage(self: *Self) ?[:0]const u8 {
            if (c.PQerrorMessage(self.conn)) |msg| {
                return std.mem.span(msg);
            }
            return null;
        }

        pub fn socket(self: *Self) c_int {
            return c.PQsocket(self.conn);
        }

        pub fn backendPID(self: *Self) c_int {
            return c.PQbackendPID(self.conn);
        }

        pub fn host(self: *Self) [:0]const u8 {
            return std.mem.span(c.PQhost(self.conn));
        }

        pub fn port(self: *Self) [:0]const u8 {
            return std.mem.span(c.PQport(self.conn));
        }

        pub fn dbname(self: *Self) [:0]const u8 {
            return std.mem.span(c.PQdb(self.conn));
        }
    };
}

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
    polltype: c.PostgresPollingStatusType,
    status: StartupStatus = StartupStatus.CONNECTING,

    const Self = @This();

    pub fn new(conn: *AsyncConn) Self {
        var self: Self = undefined;
        self.init();
        _ = self.update(conn);
        return self;
    }

    pub fn init(self: *Self) void {
        self.* = .{ .polltype = 0 };
    }

    pub fn update(self: *Self, conn: *AsyncConn) bool {
        const pq_status = conn.status();
        var status_update = switch (pq_status) {
            c.CONNECTION_OK => StartupStatus.CONNECTED,
            c.CONNECTION_BAD => StartupStatus.ERROR,
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
            c.PGRES_POLLING_FAILED => StartupStatus.ERROR,
            c.PGRES_POLLING_OK => StartupStatus.CONNECTED,
            else => StartupStatus.CONNECTING,
        };
        const changed = self.status != status_update;
        self.status = status_update;
        return changed;
    }

    pub fn getEventMask(self: *const Self) u32 {
        if (self.status == StartupStatus.CONNECTING) {
            return switch (self.polltype) {
                c.PGRES_POLLING_READING => c.WL_SOCKET_READABLE,
                else => c.WL_SOCKET_WRITEABLE,
            };
        }
        return 0;
    }
};

fn responseCodeFatal(response_code: c.ExecStatusType) bool {
    return switch (response_code) {
        c.PGRES_COMMAND_OK => false,
        c.PGRES_TUPLES_OK => false,
        c.PGRES_SINGLE_TUPLE => false,
        c.PGRES_NONFATAL_ERROR => false,
        else => response_code > 0,
    };
}

const PGQueryParams = struct {
    values: []const [*c]const u8,

    // Optional OID types of the values. Required for binary encodings.
    // In case of text encoding optional.
    types: ?[]const c.Oid = null,

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
    var types = try allocator.alloc(c.Oid, argsInfo.Struct.fields.len);

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
    result: *c.PGresult,

    const Self = @This();

    fn init(result: *c.PGresult) Self {
        return Result{ .result = result };
    }

    pub fn deinit(self: Self) void {
        c.PQclear(self.result);
    }

    pub fn status(self: Self) c.ExecStatusType {
        return c.PQresultStatus(self.result);
    }

    pub fn is_error(self: Self) bool {
        return switch (self.status()) {
            c.PGRES_EMPTY_QUERY,
            c.PGRES_COMMAND_OK,
            c.PGRES_TUPLES_OK,
            c.PGRES_COPY_OUT,
            c.PGRES_COPY_IN,
            c.PGRES_COPY_BOTH,
            c.PGRES_SINGLE_TUPLE,
            c.PGRES_NONFATAL_ERROR, // warning or notice, but no error
            => false,
            else => true,
        };
    }

    pub fn errorMessage(self: Self) ?[:0]const u8 {
        if (c.PQresultErrorMessage(self.result)) |msg| {
            return std.mem.span(msg);
        }
        return null;
    }
};

fn checkFlag(comptime pattern: anytype, value: @TypeOf(pattern)) bool {
    return (value & pattern) == pattern;
}

fn pqError(src: std.builtin.SourceLocation, conn: ?*c.PGconn) error{PGErrorStack}!void {
    const rawerr = c.PQerrorMessage(conn);
    if (rawerr == null) {
        return;
    }

    try elog.Report.init(src, c.ERROR).raise(.{
        .message = std.mem.span(rawerr),
    });
    unreachable;
}
