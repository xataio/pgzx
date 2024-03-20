My Extension
============

## Development

1. Start development shell

```
$ nix develop
```

2. Relocate the postgres installation into our development environment and create a database.

```
$ pglocal && pginit
```

3. Start the local postgres development server

```
$ pgstart
```

4. Before you can build the extension you must edit the `build.zig.zon` file and update the hash value. To do so we run `zig build` and copy the hash value from the error message into the `build.zig.zon` file:

```
$ zig build

Fetch Packages... pgzx... build.zig.zon:13:20: error: url field is missing corresponding hash field
            .url = "https://github.com/xataio/pgzx/archive/main.tar.gz",
                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
note: expected .hash = "122097e7141a57b8170ca5288f5514b2b5b27b730a78d2aae7a5f54675ae1614c690",
```

5. Compile and install the extension into the development server

```
$ zig build -freference-trace -p $PG_HOME
...

$ psql -U postgres -c 'CREATE EXTENSION my_extension'
```

6. Verify extension is working

```
$ psql -U postgres -c 'SELECT hello()'
```

7. Stop development server

```
$ pgstop
```
