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

`pgzx` is a library for developing PostgreSQL extensions written in Zig. It provides a set of utilities (e.g. error handling, memory allocators, wrappers) as well as a development environment that simplifies integrating with the Postgres code base.

## Why Zig?

[Zig](https://ziglang.org/) is a small and simple language that aims to be a "modern C" and make system-level code bases easier to maintain. It provides safe memory management, compilation time code execution (comptime), and a rich standard library.

Zig can interact with C code quite naturally: it supports the C ABI, can work with C pointers and types directly, it can import header files and even translate C code to Zig code. Thanks to this interoperability, a Postgres extension written in Zig can, theoretically, accomplish anything that a C extension can. This means you get full power AND a modern language and standard library to write your extension.

While in theory you can write any extension in Zig that you could in C, in practice you will need to make sense of a lot of Postgres internals in order to know how to correctly use them from Zig. Also, Postgres makes extensive use of macros, and not all of them can be translated automatically. This is where pgzx comes in: it provides a set of Zig modules that make the development of Postgres Extensions in Zig much simpler.

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

This project uses [Nix flakes](https://nixos.wiki/wiki/Flakes) to manage build dependencies and provide a development shell. We provide a template for you to initialize a new Zig based Postgres extension project which allows you to reuse some of the utilities we're using.

Before getting started we would recommend you familiarize yourself with the projects setup first. To do so, please start with the [Contributing](#contributing) section.   

We will create a new project folder for our new extension and initialize the folder using the projects template:

```
$ mkdir my_extension
$ cd my_extension
$ nix flake init -t github:xataio/pgzx
```

This step will create a working extension named 'my_extension'. The extension exports a hello world function named `hello()`.

The templates [README.md](./nix/templates/init/README.md) file already contains instructions on how to enter the development shell, build, and test the extension. You can follow the instructions and verify that your setup is functioning. Do not forget to use `pgstop` before quitting the development shell.

The development shell declares a few environment variables used by the project (see [devshell.nix](./devshell.nix)):
- `PRJ_ROOT`: folder of the current project. If not set some shell scripts will
  ask `git` to find the projects folder. Some scripts use this environment variable to ensure that you can run the script from within any folder within your project.
- `PG_HOME`: Installation path of your postgres instance. When building postgres from scratch this matches the 
path prefix used by `make install`. When using the development shell we will relocate/build the postgres extension into the `./out` folder and create a symlink `./out/default` to the local version. If you plan to build and install the extension with another PostgreSQL installation set `PG_HOME=$(dirname $(pg_config --bindir))`.


Next we want to rename the project to match our extension name. To do so, update the file names in the `extension` folder, and replace `my_extension` with your project name in the `README.md`, `build.zig`, `build.zig.zon`, and extensions SQL file.

### Logging and error handling

Postgres [error reporting functions](https://www.postgresql.org/docs/current/error-message-reporting.html) are used to report errors and log messages. They have typical logging functionality like log levels and formatting, but also Postgres specific functionality, like error reports that can be thrown and caught like exceptions. `pgzx` provides a wrapper around these functions that makes it easier to use from Zig.

Simple logging can be done with functions like [Log][docs_Log], [Info][docs_Info], [Notice][docs_Notice], [Warning][docs_Warning], for example:

```zig
    elog.Info(@src(), "input_text: {s}\n", .{input_text});
```

Note the `@src()` built-in which provides the file location. This will be stored in the error report.

To report errors during execution, use the [Error][docs_Error] or [ErrorThrow][docs_ErrorThrow] functions. The latter will throw an error report, which can be caught by the Postgres error handling system (explained below). Example with `Error`:

```zig
    if (target_char.len > 1) {
        return elog.Error(@src(), "Target char is more than one byte", .{});
    }
```

The elog module also exports functions that resemble the C API including functions like `ereport`, `errcode`, or `errmsg`.

If you browse through the Postgres source code, you'll see the [PG_TRY / PG_CATCH / PG_FINALLY](https://github.com/postgres/postgres/blob/master/src/include/utils/elog.h#L318) macros used as a form of "exception handling" in C, catching errors raised by the [ereport](https://www.postgresql.org/docs/current/error-message-reporting.html) family of functions. These macros make use of long jumps (i.e. jumps across function boundaries) to the "catch/finally" destination. This means we need to be careful when calling Postgres functions from Zig. For example, if the called C function raises an `ereport` error, the long jump might skip the Zig code that would have cleaned up resources (e.g. `errdefer`).

pgzx offers an alternative Zig implementation for the PG_TRY family of macros. This typically looks in code something like this:

```zig
    var errctx = pgzx.err.Contextelog.Log
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
