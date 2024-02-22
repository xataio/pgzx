const std = @import("std");
const pgzx = @import("pgzx");
const pg = pgzx.c;

comptime {
    pgzx.fmgr.PG_MODULE_MAGIC();
}

var prev_ExecutorStart_hook: pg.ExecutorStart_hook_type = null;
var prev_ExecutorFinish_hook: pg.ExecutorFinish_hook_type = null;
var prev_ExecutorCheckPerms_hook: pg.ExecutorCheckPerms_hook_type = null;

pub const std_options = .{
    .log_level = .debug,
    .logFn = pgzx.elog.logFn,
};

const Commands = enum {
    CMD_UNKNOWN,
    CMD_SELECT,
    CMD_UPDATE,
    CMD_INSERT,
    CMD_DELETE,
    CMD_MERGE,
    CMD_UTILITY,
    CMD_NOTHING,
};

const AuditEvent = struct {
    command: Commands,
    commandText: []const u8,
    relations: ?std.ArrayList(RelEntry) = null,

    queryContext: ?pg.MemoryContext = null,

    memctx: pgzx.mem.MemoryContextAllocator,
};

const RelEntry = struct {
    rel_oid: pg.Oid,
    rel_name: []u8,
    rel_namespace_oid: pg.Oid,
    rel_namespace_name: []u8,
};

const EventsError = error{
    EventNotFound,
};

var audit_events_list: ?std.ArrayList(*AuditEvent) = null;
var global_memctx: pgzx.mem.MemoryContextAllocator = undefined;

const settings = struct {
    var log_statement: pgzx.guc.CustomBoolVariable = undefined;

    fn register() void {
        log_statement.register(.{
            .name = "pgaudit_zig.log_statement",
            .short_desc =
            \\ Specifies whether logging will include the statement text and
            \\ parameters. Depending on requirements, the full statement text might
            \\ not be required in the audit log. The default is true.
            ,
            .initial_value = true,
            .flags = pg.PGC_SUSET,
        });
    }
};

pub export fn _PG_init() void {
    // Setup logging. We want to see all messages in the client session ;)
    pgzx.elog.options.postgresLogFnLeven = pg.LOG;

    prev_ExecutorStart_hook = pg.ExecutorStart_hook;
    pg.ExecutorStart_hook = pgaudit_zig_ExecutorStart_hook;

    prev_ExecutorFinish_hook = pg.ExecutorFinish_hook;
    pg.ExecutorFinish_hook = pgaudit_zig_ExecutorFinish_hook;

    prev_ExecutorCheckPerms_hook = pg.ExecutorCheckPerms_hook;
    pg.ExecutorCheckPerms_hook = pgaudit_zig_ExecutorCheckPerms_hook;

    std.log.debug("pgaudit_zig: hooks installed\n", .{});
}

// Return the session local list of audit events. Initialized the memory context and the list if necessary.
fn getAuditList() error{PGErrorStack}!*std.ArrayList(*AuditEvent) {
    if (audit_events_list) |*list| {
        return list;
    }

    settings.register();

    // Create a memory context for the global list. The parent is TopMemoryContext, so it will never be destroyed.
    global_memctx = pgzx.mem.createAllocSetContext("pgaudit_zig_context_global", .{ .parent = pg.TopMemoryContext }) catch |err| {
        return pgzx.elog.Error(@src(), "pgaudit_zig: failed to create memory context: {}\n", .{err});
    };
    audit_events_list = std.ArrayList(*AuditEvent).init(global_memctx.allocator());
    return &audit_events_list.?;
}

fn executorStartHook(queryDesc: [*c]pg.QueryDesc, eflags: c_int) !void {
    var memctx = try pgzx.mem.createAllocSetContext("pgaudit_zig_context", .{ .parent = pg.CurrentMemoryContext });
    const allocator = memctx.allocator();

    const commandText = try allocator.dupe(u8, std.mem.span(queryDesc.*.sourceText));

    const event = try allocator.create(AuditEvent);
    event.* = .{
        .command = @enumFromInt(queryDesc.*.operation),
        .commandText = commandText,
        .memctx = memctx,
    };

    var audit_list = try getAuditList();
    try audit_list.append(event);

    if (prev_ExecutorStart_hook) |hook| {
        hook(queryDesc, eflags);
    } else {
        // we still need to call the standard hook
        pg.standard_ExecutorStart(queryDesc, eflags);
    }

    // reading queryDesc.*.estate.*.es_query_cxt needs to happen *after* calling the standard hook.
    // However, we need the event in the list before calling the standard hook, because it calls the CheckPerms hook.
    event.queryContext = queryDesc.*.estate.*.es_query_cxt;
    try memctx.registerAllocResetCallback(
        queryDesc.*.estate.*.es_query_cxt,
        pgaudit_zig_MemoryContextCallback,
    );
}

fn pgaudit_zig_ExecutorStart_hook(queryDesc: [*c]pg.QueryDesc, eflags: c_int) callconv(.C) void {
    std.log.debug("pgaudit_zig: ExecutorStart_hook\n", .{});

    executorStartHook(queryDesc, eflags) catch |err| {
        std.log.err("pgaudit_zig: failed to call executorStartHook: {}\n", .{err});
    };
}

fn executorCheckPermsHook(rangeTables: [*c]pg.List, rtePermInfos: [*c]pg.List, violation: bool) error{ OutOfMemory, EventNotFound, PGErrorStack }!bool {
    _ = violation;
    _ = rtePermInfos;

    const list = try getAuditList();
    const event = list.getLast();
    var allocator = event.memctx.allocator();

    var relList = std.ArrayList(RelEntry).init(allocator);
    errdefer relList.deinit();

    var errctx = pgzx.err.Context.init();
    defer errctx.deinit();
    if (errctx.pg_try()) {
        var it = pgzx.PointerListOf(pg.RangeTblEntry).init(rangeTables).iter();
        while (it.next()) |rte| {
            const relOid = rte.?.relid;
            const relNamespaceOid = pg.get_rel_namespace(relOid);

            if (pg.IsCatalogNamespace(relNamespaceOid) or relOid == 0 or relNamespaceOid == 0) {
                continue;
            }

            const namespaceName = pg.get_namespace_name(relNamespaceOid);
            const relName = pg.get_rel_name(relOid);

            const relEntry = RelEntry{
                .rel_oid = relOid,
                .rel_name = try allocator.dupe(u8, std.mem.span(relName)),
                .rel_namespace_oid = relNamespaceOid,
                .rel_namespace_name = try allocator.dupe(u8, std.mem.span(namespaceName)),
            };
            try relList.append(relEntry);

            std.log.debug("pgaudit_zig: ExecutorCheckPerms_hook: relNamespaceOid: {}, relOid: {}\n", .{ relNamespaceOid, relOid });
            std.log.debug("pgaudit_zig: ExecutorCheckPerms_hook: namespace: {s}, rel: {s}\n", .{ namespaceName, relName });
        }
        event.relations = relList;
    } else {
        return errctx.errorValue();
    }

    return true;
}

pub fn pgaudit_zig_ExecutorCheckPerms_hook(rangeTables: [*c]pg.List, rtePermInfos: [*c]pg.List, violation: bool) callconv(.C) bool {
    std.log.debug("pgaudit_zig: ExecutorCheckPerms_hook\n", .{});

    return executorCheckPermsHook(rangeTables, rtePermInfos, violation) catch |err| {
        // Forward reported errors to the postgres error stack.
        pgzx.elog.throwAsPostgresError(@src(), err);
        unreachable;
    };
}

fn pgaudit_zig_ExecutorFinish_hook(queryDesc: [*c]pg.QueryDesc) callconv(.C) void {
    std.log.debug("pgaudit_zig: ExecutorFinish_hook\n", .{});

    const queryContext = queryDesc.*.estate.*.es_query_cxt;

    const audit_list = getAuditList() catch |e| pgzx.elog.throwAsPostgresError(@src(), e);
    const event = popEvent(audit_list, queryContext) catch |err| {
        pgzx.elog.Log(@src(), "pgaudit_zig: failed to pop event from audit_events_list: {}\n", .{err});
        return;
    };
    defer freeEvent(event);

    logAuditEvent(event) catch |err| {
        std.log.err("pgaudit_zig: failed to log audit event: {}\n", .{err});
    };
}

fn popEvent(event_list: *std.ArrayList(*AuditEvent), memctx: pg.MemoryContext) error{EventNotFound}!*AuditEvent {
    const idx = try findEvent(event_list, memctx);
    return event_list.swapRemove(idx);
}

fn findEvent(event_list: *std.ArrayList(*AuditEvent), memctx: pg.MemoryContext) error{EventNotFound}!usize {
    for (event_list.items, 0..) |event, i| {
        if (event.queryContext) |cxt| {
            if (cxt == memctx) {
                return i;
            }
        }
    }
    return error.EventNotFound;
}

fn freeEvent(event: *AuditEvent) void {
    std.log.debug("pgaudit_zig: freeEvent\n", .{});

    // destroying the memory context frees everything we have allocated in it.
    var memctx = event.memctx;
    memctx.deinit();
}

fn pgaudit_zig_MemoryContextCallback(arg: ?*anyopaque) callconv(.C) void {
    std.log.debug("pgaudit_zig: MemoryContextCallback\n", .{});

    const memctx: pg.MemoryContext = @alignCast(@ptrCast(arg));
    const list = getAuditList() catch return;
    const event = popEvent(list, memctx) catch |err| {
        if (err == error.EventNotFound) {
            return;
        }
        std.log.err("pgaudit_zig: failed to pop event in MemoryContextCallback: {}\n", .{err});
        return;
    };
    freeEvent(event);
}

fn eventToJSON(event: *AuditEvent, writer: std.ArrayList(u8).Writer) !void {
    _ = try writer.write("{\"operation\": ");
    try std.json.encodeJsonString(@tagName(event.command), .{}, writer);

    if (event.relations) |relations| {
        _ = try writer.write(", \"relations\": [");

        for (relations.items, 0..) |rel, i| {
            if (i != 0) {
                _ = try writer.write(", ");
            }
            _ = try writer.write("{");
            _ = try writer.write("\"relOid\": ");
            try std.fmt.format(writer, "{d}", .{rel.rel_oid});
            _ = try writer.write(", \"relname\": ");
            try std.json.encodeJsonString(rel.rel_name, .{}, writer);
            _ = try writer.write(", \"namespaceOid\": ");
            try std.fmt.format(writer, "{d}", .{rel.rel_namespace_oid});
            _ = try writer.write(", \"relnamespaceName\": ");
            try std.json.encodeJsonString(rel.rel_namespace_name, .{}, writer);
            _ = try writer.write("}");
        }
        _ = try writer.write("]");
    }

    if (settings.log_statement.value) {
        _ = try writer.write(", \"commandText\": ");
        try std.json.encodeJsonString(event.commandText, .{}, writer);
    }
    _ = try writer.write("}");
}

fn logAuditEvent(event: *AuditEvent) !void {
    std.log.debug("pgaudit_zig: logAuditEvent\n", .{});

    var string = std.ArrayList(u8).init(pgzx.mem.PGCurrentContextAllocator);
    defer string.deinit();
    const writer = string.writer();

    try eventToJSON(event, writer);

    std.log.debug("pgaudit_zig: logAuditEvent: {s}\n", .{string.items});
}

const Tests = struct {

    // Test that exercises adding, searching, and removing an event from the global list.
    pub fn testAddAndRemoveEvent() !void {
        var memctx = try pgzx.mem.createAllocSetContext("pgaudit_zig_tests_context", .{ .parent = pg.CurrentMemoryContext });
        defer memctx.deinit();
        const allocator = memctx.allocator();

        const query_ctx = memctx.context();

        const event = try allocator.create(AuditEvent);
        event.* = .{
            .command = Commands.CMD_SELECT,
            .commandText = "select test()",
            .memctx = memctx,
            .queryContext = query_ctx,
        };

        const list = try getAuditList();
        try list.append(event);

        const last = list.getLast();
        try std.testing.expectEqual(event, last);

        const popped = try popEvent(list, query_ctx);
        try std.testing.expectEqual(event, popped);

        try std.testing.expectEqual(0, list.items.len);
    }

    // Test for eventToJSON function.
    pub fn testEventToJSON() !void {
        var memctx = try pgzx.mem.createAllocSetContext("pgaudit_zig_tests_context", .{ .parent = pg.CurrentMemoryContext });
        defer memctx.deinit();
        const allocator = memctx.allocator();

        var event = AuditEvent{
            .command = Commands.CMD_SELECT,
            .commandText = "select test()",
            .memctx = memctx,
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();
        const writer = string.writer();

        try eventToJSON(&event, writer);

        const expected =
            \\{"operation": "CMD_SELECT", "commandText": "select test()"}
        ;
        try std.testing.expectEqualSlices(u8, expected, string.items);
    }
};

comptime {
    pgzx.testing.registerTests(Tests, @import("build_options").testfn);
}
