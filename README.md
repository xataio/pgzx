<div align="center">
  <img src="brand-kit/banner/pgzx-banner-github@2x.png" alt="pgzx logo" />
</div>

<p align="center">
  <a href="https://github.com/xataio/pgzx/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-green" alt="License - Apache 2.0"></a>&nbsp;
  <a href="https://github.com/xataio/pgzx/actions?query=branch%3Amain"><img src="https://github.com/xataio/pgzx/actions/workflows/check.yaml/badge.svg" alt="CI Build"></a> &nbsp;
  <a href="https://xata.io/discord"><img src="https://img.shields.io/discord/996791218879086662?label=Discord" alt="Discord"></a> &nbsp;
  <a href="https://twitter.com/xata"><img src="https://img.shields.io/twitter/follow/xata?style=flat" alt="X (formerly Twitter) Follow" /> </a>
</p>


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

## Docs


The reference documentation is available at [here](https://xataio.github.io/pgzx/).

We recommend checking the examples in the section above to understand how to use pgzx. The next sections contain a high-level walkthrough of the most important utilities and how they relate to the Postgres internals.

### Getting Started

This project uses [Nix flakes](https://nixos.wiki/wiki/Flakes) to manage build dependencies and provide a development shell. We provide a template for you initialize a new Zig based Postgres extension project, which allows you to reuse some of the utilities we're using.

Before getting started we would recommend you to familiarize yourself with the projects setup first. To do so, please start with the [Contributing][#contributing] section.   

We will create a new project folder for our new extension and initialize the folder using the projects template:

```
$ mkdir my_extension
$ cd my_extension
$ nix flake init -t github:xataio/pgzx
```

This step will create a working extension named 'my_extension'. The extension exports a hello world function named 'hello()'.

The templates [README.md](./nix/templates/init/README.md) file already contains instructions on how to enter the development shell, build, and test the extension. You can follow the instructions and verify that your setup is functioning. Do not forget to use `pgstop` before quitting the development shell.

Next we want to rename the project to match our extension name. To do so update the file names in the `extension` folder, and replace `my_extension` with you project name in the `README.md`, `build.zig`, `build.zig.zon` and extensions SQL file.

### Logging and error handling

Postgres [error reporting functions](https://www.postgresql.org/docs/current/error-message-reporting.html) are used to report errors and log messages. They have usual logging functionality like log levels and formatting, but also Postgres specific functionality, like error reports that can be thrown and caught like exceptions. `pgzx` provides a wrapper around these functions that makes it easier to use from Zig.

Simple logging can be done with functions like [Log][docs_Log], [Info][docs_Info], [Notice][docs_Notice], [Warning][docs_Warning], for example:

```zig
    elog.Info(@src(), "input_text: {s}\n", .{input_text});
```

Note the `@src()` built-in which provides the file location. This will be stored in the error report.

To report errors during execution, use the [Error][docs_Error] or [ErrorThrow][docs_ErrorThrow] functions. The latter will throw an error report, which can be caught by the Postgres error handling system (explained) below). Example with `Error`:

```zig
    if (target_char.len > 1) {
        return elog.Error(@src(), "Target char is more than one byte", .{});
    }
```

If you browse through the Postgres source code, you'll see the [PG_TRY / PG_CATCH / PG_FINALLY](https://github.com/postgres/postgres/blob/master/src/include/utils/elog.h#L318) macros used as a form of "exception handling" in C, catching errors raised by the [ereport](https://www.postgresql.org/docs/current/error-message-reporting.html) family of functions. These macros make use of long jumps (i.e. jumps across function boundaries) to the "catch/finally" destination. This means we need to be careful when calling Postgres functions from Zig. For example, if the called C function raises an `ereport` error, the long jump might skip the Zig code that would have cleaned up resources (e.g. `errdefer`).

pgzx offers an alternative Zig implementation for the PG_TRY family of macros. This typically looks in code something like this:

```zig
    var errctx = pgzx.err.Context.init();
    defer errctx.deinit();
    if (errctx.pg_try()) {
        // zig code that calls several Postgres C functions.
    } else {
        return errctx.errorValue();
    }
```

The above code pattern makes sure that we catch any errors raised by Postgres functions and return them as Zig errors. This way, we make sure that all the `defer` and `errdefer` code in the caller(s) is executed as expected. For more details, see the documentation for the [pgzx.err.Context][docs_Context] struct.

The above code pattern is implemented in a [wrap][docs_wrap] convenience function which takes a function and its arguments, and executes it in a block like the above. For example:

```zig
    try pgzx.err.wrap(myFunction, .{arg1, arg2});
```

### Memory context allocators

Postgres uses a [memory context system](https://github.com/postgres/postgres/blob/master/src/backend/utils/mmgr/README) to manage memory. Memory allocated in a context can be freed all at once (for example, when a query execution is finished), which simplifies memory management significantly, because you only need to track contexts, not individual allocations. Contexts are also hierarchical, so you can create a context that is a child of another context, and when the parent context is freed, all children are freed as well.

pgzx offers custom wrapper Zig allocators that use Postgres' memory context system. The [pgzx.mem.createAllocSetContext][docs_createAllocSetContext] function creates an [pgzx.mem.MemoryContextAllocator][docs_MemoryContextAllocator] that you can use as a Zig allocator. For example:

```zig
    var memctx = try pgzx.mem.createAllocSetContext("zig_context", .{ .parent = pg.CurrentMemoryContext });
    const allocator = memctx.allocator();
```

In the above, note the use of `pg.CurrentMemoryContext` as the parent context. This is the context of the current query execution, and it will be freed when the query is finished. This means that the memory allocated with `allocator` will be freed at the same time.

It's also possible to register a callback for when the memory context is destroyed or reset. This is useful to free or close resources that are tied to the context (e.g. sockets). pgzx provides an utility to register a callback:

```zig
    try memctx.registerAllocResetCallback(
        queryDesc.*.estate.*.es_query_cxt,
        pgaudit_zig_MemoryContextCallback,
    );
```

### Function manager

pgzx has utilities for registering functions, written Zig, that are then available to call over SQL. This is done, for example, via the [PG_FUNCTION_V1][docs_PG_FUNCTION_V1] function:

```
comptime {
    pgzx.PG_FUNCTION_V1("my_function", myFunction);
}
```

The parameters are received from Postgres serialized, but pgzx automatically deserializes them into Zig types.

### Testing your extension

pgzx provides two types of automatic tests: pg_regress tests and unit tests. The [pg_regress tests](https://www.postgresql.org/docs/current/regress.html) work similar with the way they work for C extensions. You provide inputs in a `sql` folder and expected outputs in the `expected` folder, and then you can run them like this:

```sh
zig build pg_regress
```

Under the hood, this calls the `pg_regress` tool from the Postgres build.

For unit tests, we would like to run tests in a Postgres instance, so that the unit tests compile in the same environment as the tested code, and so that the tests can call Postgres APIs. In order to do this, pgzx registers a custom `run_tests` function via the Function manager. This function can be called from SQL (`SELECT run_tests();`) and it will run the unit tests.

A test suite is a Zig struct for which each function whose name starts with `test` is a unit test. To register a test suite, you would typically do something like this:

```zig
comptime {
    pgzx.testing.registerTests(@import("build_options").testfn, .{Tests});
}
``` 

The `build_options.testfn` options should be defined via `build.zig`. For an example on how to do that, check out the `char_count_zig` or the `pgaudit_zig` sample extensions.

Note that you can only call the `pgzx.testing.registerTests` function once per extension. If you extension has multiple modules/files, you should call it like this:

```zig
 comptime {
    pgzx.testing.registerTests(@import("build_options").testfn, .{
         @import("module1.zig").Tests,
         @import("module2.zig").Tests,
         @import("module2.zig").Tests,
    });
}
```

To run the unit tests, provided that you are using our sample `build.zig`, you can run:

```sh
zig build unit -p $PG_HOME
```

Behind the scenes, this builds the extension with the `testfn` build option set to `true`, deploys it in the Postgres instance, and then calls `SELECT run_tests();` to run the tests.

## Status/Roadmap

pgzx is currently under heavy development by the [Xata](https://xata.io) team. If you want to try Zig for writing PostgreSQL extensions, it is easier with pgzx than without, but expect breaking changes and potential instability. If you need help, join us on the [Xata discord](https://xata.io/discord).

* Utilities
  * [ ] Postgres versions (compile and test)
    * [ ] Postgres 14
    * [ ] Postgres 15
    * [ ] Postgres 16
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
  * [x] Compile example extensions against the Postgres source code
  * [x] Build target to run Postgres regression tests
  * [x] Run unit tests in the Postgres environment
  * [ ] Provide a standard way to test extensions from separate repos
* Packaging
  * [x] Add support for Zig packaging



## Contributing

### Develpment shell and local installation

We use Nix to provide a local development shell.
This ensures that we have a stable environment with all dependencies available
in the expected versions. This is especially important with Zig, which is still
in development.

For this purpose it is possible do use this project as input in downstream
flake files as well.

The tools we use also require some environment variables set, which are already
pre-configured in the develpment shell.

We would recommend the [nix-installer from DeterminateSystems](https://github.com/DeterminateSystems/nix-installer). The
installer enables Nix Flakes (used by this project) out of the box and also
provides an uninstaller.

If you want to try out the project without having to install Nix on your
system, you can do so using Docker. You can build the docker image by running
the `dev/docker/build.sh` script. The docker image is names `pgzx:latest`.

To enter the develpment shell run:

```
$ nix develop
```

If you want to use the docker instead, run:

```
$ ./dev/docker/run.sh
```


NOTE:
We also provide an `.envrc` file to automatically enter the development shell when entering
the projects folder. If you use direnv you can enable the environment via `direnv allow`.

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

Having a local installation we want to create a local database and user:

```
$ pginit
...
```

This did create a local database named `postgres`. The script allows us to configure an alternative name for the cluster, database or user. This allows us to create multiple clusters within our current installation.

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

```sh
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

[docs_Log]: https://xataio.github.io/pgzx/#A;pgzx:elog.Log
[docs_Info]: https://xataio.github.io/pgzx/#A;pgzx:elog.Info
[docs_Notice]: https://xataio.github.io/pgzx/#A;pgzx:elog.Notice
[docs_Warning]: https://xataio.github.io/pgzx/#A;pgzx:elog.Warning
[docs_Error]: https://xataio.github.io/pgzx/#A;pgzx:elog.Error
[docs_ErrorThrow]: https://xataio.github.io/pgzx/#A;pgzx:elog.ErrorThrow
[docs_Context]: https://xataio.github.io/pgzx/#A;pgzx:err.Context
[docs_wrap]: https://xataio.github.io/pgzx/#A;pgzx:err.wrap
[docs_createAllocSetContext]: https://xataio.github.io/pgzx/#A;pgzx:mem.createAllocSetContext
[docs_MemoryContextAllocator]: https://xataio.github.io/pgzx/#A;pgzx:mem.MemoryContextAllocator
[docs_PG_FUNCTION_V1]: https://xataio.github.io/pgzx/#A;pgzx:PG_FUNCTION_V1
