# Postgres Zig Extensions utilities

## Develpment shell and local installation

We use Nix to provide a local development shell. But you should be able to run
the following scripts without the development shell.

TODO: test the scripts without development shell

TODO: recommend nix installer

TODO: support to create develpment shell in docker container

Still, we would recommend to use the development shell as we already provide
all compatible dependencies that you will need for developing within this
repository.
The tools we use also require some environment variables set, which are already
pre-configured in the develpment shell.

To enter the develpment shell run:

```
$ nix develop
```

NOTE:
We also provide an `.envrc` file to automatically enter the development shell when entering
the projects folder.

The nix configuration already installs PostgresSQL, but for testing we want to
have a local postgres installation where we can install our test extensions in.

We use `pglocal` to relocate the existing installation into our development environment:

```
$ pglocal
...

$ ls out
16  default
```

The `out/default` folder is a symlink to the postgres installation currently in use.

Having a local installation we want to create a local database and user that we can run:

```
$ pginit
...
```

This did create a local database names and `postgres` user. The script allows us to configure an alternative name for the cluster, database or user. This allows us to create multiple clusters within our current installation.

We can start and stop the database using `pgstart` and `pgstop`. Let's test our current setup:

```
$ pgstart
$ psql  -U postgres -c 'select version()'
                                         version
-----------------------------------------------------------------------------------------
 PostgreSQL 16.1 on aarch64-apple-darwin22.6.0, compiled by clang version 16.0.6, 64-bit
(1 row)
```

This project has a few example extensions. We will install and test the `char_count_zig` extension next:

```
$ cd examples/char_count_zig
$ zig build -freference-trace -p $PG_HOME
$ psql  -U postgres -c 'CREATE EXTENSION char_count_zig;'
CREATE EXTENSION
$ psql  -U postgres -c "SELECT char_count_zig('aaabc', 'a');"
INFO:  input_text: aaabc

INFO:  target_char: a

INFO:  Target char len: 1

 char_count_zig
----------------
              3
(1 row)
```

The sample extension also supports pg_regress bases testing:

TODO: fix me currently broken with the local setup. 
