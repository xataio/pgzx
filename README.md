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
