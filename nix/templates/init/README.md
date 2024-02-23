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

4. Compile and install the extension into the development server

```
$ zig build -freference-trace -p $PG_HOME
...

$ psql -U postgres -c 'CREATE EXTENSION my_extension'
```

5. Verify extension is working

```
$ psql -U postgres -c 'SELECT hello()'
```

6. Stop development server

```
$ pgstop
```
