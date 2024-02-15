# char_count_zig - Minimal PostgreSQL extension using Zig

This is a sample PostgreSQL extension written in Zig. It provides a function `char_count_zig` that counts the number of occurrences of a character in a string. The code is a port using pgzx of the sample `char_count` C extension from [this tutorial](https://www.highgo.ca/2019/10/01/a-guide-to-create-user-defined-extension-modules-to-postgres/).

## Functionality

The function `char_count_zig` takes two arguments: a string and a character. It returns the number of occurrences of the character in the string:

```sql
SELECT char_count_zig('Hello, World', 'o');
 char_count_zig
----------------
              2
(1 row)
```

## Running

To test the extension, follow first the development shell instructions in the [pgzx README][pgzx_Development]. The following commands assume you are in the nix shell (run `nix develop`).

Run in the folder of the extension:

```sh
cd examples/char_count_zig
zig build -freference-trace -p $PG_HOME
```

This will build the extension and install the extension in the Postgres instance.

Then, connect to the Postgres instance:

```sh
psql -U postgres
```

At the Postgres prompt, create the extension:

```sql
CREATE EXTENSION char_count_zig;
```

## Code walkthrough

### Control files

The overall structure of the extension looks very similar to a C extension:

```
├── extension
│   ├── char_count_zig--0.1.sql
│   └── char_count_zig.control
```

The `extension` folder contains the control files, which are used by Postgres to manage the extension. The `char_count_zig.control` file contains metadata about the extension, such as its name and version. The `char_count_zig--0.1.sql` file contains the SQL commands to create and drop the extension.

### Zig code

The `main.zig` file starts with the following `comptime` block:

```zig
comptime {
    pgzx.PG_MODULE_MAGIC();

    pgzx.PG_FUNCTION_V1("char_count_zig", char_count_zig);
}
```

The [pgzx.PG_MODULE_MAGIC][docs_PG_MODULE_MAGIC] function returns an exported `PG_MAGIC` struct that PostgreSQL uses to recognize the library as a Postgres extension. 

The [pgzx.PG_FUNCTION_V1][docs_PG_FUNCTION_V1] macro defines the `char_count_zig` function as a Postgres function. This function does the heavy lifting of deserializing the input arguments and transforming them in Zig slices. 

This means the implementation of the `char_count_zig` function is quite simple:

```zig
fn char_count_zig(input_text: []const u8, target_char: []const u8) !u32 {
    if (target_char.len > 1) {
        return pgzx.elog.Error(@src(), "Target char is more than one byte", .{});
    }

    pgzx.elog.Info(@src(), "input_text: {s}\n", .{input_text});
    pgzx.elog.Info(@src(), "target_char: {s}\n", .{target_char});
    pgzx.elog.Info(@src(), "Target char len: {}\n", .{target_char.len});

    var count: u32 = 0;
    for (input_text) |char| {
        if (char == target_char[0]) {
            count += 1;
        }
    }
    return count;
}
```

In the above, note the use of [pgzx.elog.Error][docs_Error] and [pgzx.elog.Info][docs_Info] to report errors and info back to the user. The rest of the function is idiomatic Zig code.

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

