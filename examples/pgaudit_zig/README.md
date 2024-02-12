# pgaudit_zig - Sample PostgreSQL extension using Zig

This is a sample PostgreSQL extension written in Zig. It is not meant for production use (use pgaudit), but rather to show how to use pgzx on a more complex example. It follows roughly the same approach as pgaudit, but it is not a complete implementation.

## Functionality

The extension hooks into the executor and logs the query that was executed. For example, for a query like this:

```sql
select * from foo,bar;
```

It logs, as json:

```json
{
  "operation": "CMD_SELECT",
  "relations": [
    {
      "relOid": 24596,
      "relname": "foo",
      "namespaceOid": 2200,
      "relnamespaceName": "public"
    },
    {
      "relOid": 24601,
      "relname": "bar",
      "namespaceOid": 2200,
      "relnamespaceName": "public"
    }
  ],
  "commandText": "select * from foo,bar;"
}
```

Note that tables (relations in internal Postgres terminology) accessed are logged in an array.

## Code walkthrough

Here are the key code elements and how they make use of the pgzx helpers. When reviewing the code, it is helpful to have a look at the C code in the pgaudit extension, as well as at the Postgres source code.

### PG_MAGIC struct

In order for Postgres to know how to load the extension, it needs to export a "magic" struct as `PG_MAGIC`. pgzx makes it easy to do this:

```zig
comptime {
    pgzx.fmgr.PG_MODULE_MAGIC();
}
```

### Logging

pgrx provides an elog utility that integrates with Postgres' logging system. It is initialized like this:

```zig
pub const std_options = .{
    .log_level = .debug,
    .logFn = pgzx.elog.logFn,
```

Then you can use the normal standard library logging functions, like `std.log.debug` and the output will be sent to the Postgres logs.

Something that is sometimes useful during debugging is to send the logs to the interactive `psql` session. This is done by setting the level to NOTICE:

```zig
    // Setup logging. We want to see all messages in the client session ;)
    pgzx.elog.options.postgresLogFnLeven = pg.NOTICE;
```

### Custom settings

Postgres extensions can define custom settings via variables. Here is the code that registers a custom bool variable:

```zig
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
```

The register function is called in `_PG_init`, and then the setting is accessed like this:

```zig
    if (settings.log_statement.value) {
        ...
    }
```

### Register hooks

In the `_PG_init` function, we register the hooks we want to use. This is done pretty much as you would do it in C code:

```zig
    prev_ExecutorStart_hook = pg.ExecutorStart_hook;
    pg.ExecutorStart_hook = pgaudit_zig_ExecutorStart_hook;

    prev_ExecutorFinish_hook = pg.ExecutorFinish_hook;
    pg.ExecutorFinish_hook = pgaudit_zig_ExecutorFinish_hook;

    prev_ExecutorCheckPerms_hook = pg.ExecutorCheckPerms_hook;
    pg.ExecutorCheckPerms_hook = pgaudit_zig_ExecutorCheckPerms_hook;
```

The hooks implementation need to respect the function signature of the hooks, and are marked with `callconv(.C)`:

```zig
fn pgaudit_zig_ExecutorStart_hook(queryDesc: [*c]pg.QueryDesc, eflags: c_int) callconv(.C) void {
    std.log.debug("pgaudit_zig: ExecutorStart_hook\n", .{});

    executorStartHook(queryDesc, eflags) catch |err| {
        std.log.err("pgaudit_zig: failed to call executorStartHook: {}\n", .{err});
    };
}
```

Note that the function calls a Zig function `executorStartHook` that is defined in the same file. This makes it easier to use Zig's error handling and results in more idiomatic Zig code.

### Allocators and memory contexts

Postgres uses a [memory context system](https://github.com/postgres/postgres/blob/master/src/backend/utils/mmgr/README) to manage memory. Memory allocated in a context can be freed all at once (for example, when a query execution is finished), which simplifies memory management significantly, because you only need to track contexts, not individual allocations. Contexts are also hierarchical, so you can create a context that is a child of another context, and when the parent context is freed, all children are freed as well.

pgzx offers custom wrapper Zig allocators that use Postgres' memory context system. For example, in the `getAuditList()` function we create a new allocator that is tied to the `TopMemoryContext`, and then use it as the allocator for a global ArrayList:

```zig
    // Create a memory context for the global list. The parent is TopMemoryContext, so it will never be destroyed.
    global_memctx = pgzx.mem.createAllocSetContext("pgaudit_zig_context_global", .{ .parent = pg.TopMemoryContext }) catch |err| {
        return pgzx.elog.Error(@src(), "pgaudit_zig: failed to create memory context: {}\n", .{err});
    };
    audit_events_list = std.ArrayList(*AuditEvent).init(global_memctx.allocator());
```

Later in the code, where we are in the context of a particular query execution, we create a child context and use it as the allocator for the memory we need. Note the use of `pg.CurrentMemoryContext` as the parent context:

```zig
    var memctx = try pgzx.mem.createAllocSetContext("pgaudit_zig_context", .{ .parent = pg.CurrentMemoryContext });
    const allocator = memctx.allocator();
```

Note also how this memory context can be placed in the event itself:

```zig
    const event = try allocator.create(AuditEvent);
    event.* = .{
        .command = @enumFromInt(queryDesc.*.operation),
        .commandText = commandText,
        .memctx = memctx,
    };
```

This makes it easy to access the allocator in other hooks, for example:

```zig
    const event = audit_events_list.getLast();
    var allocator = event.memctx.allocator();
```

In Postgres, it's possible to register a callback for when the memory context is destroyed or reset. This is useful to free or close resources that are tied to the context (e.g. sockets). pgzx provides an utility to register a callback:

```zig
    try memctx.registerAllocResetCallback(
        queryDesc.*.estate.*.es_query_cxt,
        pgaudit_zig_MemoryContextCallback,
    );
```

For another example, if you need a short-lived memory allocator that is exists only for the duration of the current function, you can see an example in the `logAuditEvent` function:

```zig
    var log_memctx = try pgzx.mem.createAllocSetContext("pgaudit_zig_context_log", .{ .parent = pg.CurrentMemoryContext });
    defer log_memctx.deinit();

    var string = std.ArrayList(u8).init(log_memctx.allocator());
    defer string.deinit();
    var writer = string.writer();
```

### Error handling

If you browse through the Postgres source code, you'll see the [PG_TRY / PG_CATCH / PG_FINALLY](https://github.com/postgres/postgres/blob/master/src/include/utils/elog.h#L318) macros used as a form of "exception handling" in C, catching errors raised by the [ereport](https://www.postgresql.org/docs/current/error-message-reporting.html) family of functions. These macros make use of long jumps (i.e. jumps across function boundaries) to the "catch/finally" destination. This means we need to be careful when calling Postgres functions from Zig. For example, if the called C function raises an `ereport` error, the long jump might skip the Zig code that would have cleaned up resources (e.g. `errdefer`).

pgzx offers an alternative Zig implementation for the PG_TRY family of macros. You can see it at work in the `executorCheckPermsHook` function:

```zig
    var errctx = pgzx.err.Context.init();
    defer errctx.deinit();
    if (errctx.pg_try()) {
        // zig code that calls several Postgres C functions.
    } else {
        return errctx.errorValue();
    }
```

The above code pattern makes sure that we catch any errors raised by Postgres functions and return them as Zig errors. For more details, see the comments in [pgzx/err.zig](https://github.com/urso/pgdc/blob/93a7d18c343f85d9dfc1529096f70239e0911856/src/lib/pgzx/err.zig#L50).

While the Postgres `ereport` function throws an exception, in Zig-land you'd typically return errors, rather than raise exceptions. For this reason, the pgzx's `pgzx.elog.Error()` function creates an error report, but also catches the error and returns a `PGErrorStack` error instead. You can see it used in the `getAuditList()` function:

```zig
    global_memctx = pgzx.mem.createAllocSetContext("pgaudit_zig_context_global", .{ .parent = pg.TopMemoryContext }) catch |err| {
        return pgzx.elog.Error(@src(), "pgaudit_zig: failed to create memory context: {}\n", .{err});
    };
```

### Walking lists

The `executorCheckPermsHook` function receives the list of tables (`rangeTable`) as a Postgres `*List`. The Postgres `List` type is somewhat similar with the Zig's standard library `ArrayList`. With pgzx you can get an iterator for the list and iterate it using a capture like this:


```zig
    var it = pgzx.PointerListOf(pg.RangeTblEntry).init(rangeTables).iter();
    while (it.next()) |rte| {
        ...
    }
```