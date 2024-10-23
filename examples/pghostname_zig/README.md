# pghostname_zig - Minimal PostgreSQL extension using Zig

This is a sample PostgreSQL extension written in Zig. It provides a function `pghostname_zig` that returns the database server's host name. The code is a port using pgzx of the `pg-hostname` C extension from [this repo](https://github.com/theory/pg-hostname/).

## Functionality

The function `pghostname_zig` takes no arguments. It returns the database server's host name:

```sql
SELECT pghostname_zig();
 pghostname_zig
----------------
 ubuntu
(1 row)
```

## Running

To test the extension, follow first the development shell instructions in the [pgzx README][pgzx_Development]. The following commands assume you are in the nix shell (run `nix develop`).

Run in the folder of the extension:

```sh
cd examples/pghostname_zig
zig build -freference-trace -p $PG_HOME
```

This will build the extension and install the extension in the Postgres instance.

Then, connect to the Postgres instance:

```sh
psql -U postgres
```

At the Postgres prompt, create the extension:

```sql
CREATE EXTENSION pghostname_zig;
```

## Code walkthrough

### Control files

The overall structure of the extension looks very similar to a C extension:

```
├── extension
│   ├── pghostname_zig--0.1.sql
│   └── pghostname_zig.control
```

The `extension` folder contains the control files, which are used by Postgres to manage the extension. The `pghostname_zig.control` file contains metadata about the extension, such as its name and version. The `pghostname_zig--0.1.sql` file contains the SQL commands to create and drop the extension.

### Zig code

The `main.zig` file starts with the following `comptime` block:

```zig
comptime {
    pgzx.PG_MODULE_MAGIC();

    pgzx.PG_FUNCTION_V1("pghostname_zig", pghostname_zig);
}
```

The [pgzx.PG_MODULE_MAGIC][docs_PG_MODULE_MAGIC] function returns an exported `PG_MAGIC` struct that PostgreSQL uses to recognize the library as a Postgres extension.

The [pgzx.PG_FUNCTION_V1][docs_PG_FUNCTION_V1] macro defines the `pghostname_zig` function as a Postgres function. This function does the heavy lifting of deserializing the input arguments and transforming them in Zig slices.

This means the implementation of the `pghostname_zig` function is quite simple:

```zig
pub fn pghostname_zig() ![]const u8 {
    var buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&buffer) catch "unknown";
    return try pgzx.mem.PGCurrentContextAllocator.dupeZ(u8, hostname);
}
```

### Testing

The extensions contains regression tests using the `pg_regress` tool, see the `sql` and `expected` folders. To run the regression tests, use the following command:

```sh
zig build pg_regress
```

[pgzx_Development]: https://github.com/xataio/pgzx/tree/main?tab=readme-ov-file#develpment-shell-and-local-installation
[docs_PG_MODULE_MAGIC]: https://xataio.github.io/pgzx/#A;pgzx:fmgr.PG_MAGIC
[docs_PG_FUNCTION_V1]: https://xataio.github.io/pgzx/#A;pgzx:PG_FUNCTION_V1
[docs_Error]: https://xataio.github.io/pgzx/#A;pgzx:elog.Error
[docs_Info]: https://xataio.github.io/pgzx/#A;pgzx:elog.Info
