# pgzx - Create Postgres Extensions with Zig!

`pgzx` is a library for developing PostgreSQL extensions written in Zig. It provides a set of utilities (e.g. error handling, memory allocators, wrappers) that simplify integrating with the Postgres code base.

## Why Zig?

[Zig](https://ziglang.org/) is a small and simple language that aims to be a "modern C" and make system-level code bases easier to maintain. It provides safe memory management, compilation time code execution (comptime), and a standard library.

Zig can interact with C code quite naturally: it supports the C ABI, can work with C pointers and types directly, it can import header files and even translate C code to Zig code. Thanks to this interoperability, a Postgres extension written in Zig can, theoretically, accomplish anything that a C extension can. This means you get full power AND a modern language and standard library to write your extension.

While in theory you can write any extension in Zig that you could in C, in practice you will need to make sense of a lot of Postgres internals in order to know how to correctly use them from Zig. Also, Postgres makes extensive use of macros, and not all of them can be translated automatically. This is where pgzx comes in: it provides a set of Zig modules that makes the development of Postgres Extensions in Zig much simpler.

## Examples

The following sample extensions (ordered from simple to complex) show how to use pgzx:

| Extension                                  | Description |
|--------------------------------------------|-------------|
| [char_count_zig](examples/char_count_zig/) | Adds a function that counts how many times a particular character shows up in a string. Shows how to register a function and how to interpret the parameters. |
| [pg_audit_zig](examples/pgaudit_zig/)      | Inspired by the pgaudit C extension, this one registers callbacks to multiple hooks and uses more advanced error handling and memory allocation patterns |

## Status/Roadmap

pgzx is currently under heavy development by the [Xata](https://xata.io) team. If you want to try Zig for writing PostgreSQL extensions, it is easier with pgzx than without, but expect breaking changes and potential instability. If you need help, join us on the [Xata discord](https://xata.io/discord).

* Utilities
  * [x] Logging
  * [x] Error handling
  * [x] Memory context allocators
  * [x] Function manager
  * [x] Background worker process
  * [x] LWLocks
  * [x] Signals and interrupts
  * [x] String formatting
  * [ ] Shared memory
  * [ ] SPI
  * Postgres data structures wrappers:
    * Array based list (List)
        * [x] Pointer list
        * [ ] int list
        * [ ] oid list
        * ...
    * [ ] Single list
    * [ ] Double list
    * [ ] Hash tables
* Development environment
  * [ ] Download and vendor Postgres source code
  * [ ] Compile extensions against the Postgres source code
* Packaging
  * [x] Add support for Zig packaging

## Docs

## Contributing

### Develpment shell and local installation

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

```
$ zig build pg_regress --verbose
# using postmaster on Unix socket, port 5432
ok 1         - char_count_test                            10 ms
1..1
# All 1 tests passed.
```
