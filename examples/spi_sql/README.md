# spi_sql - Sample extension using SPI to execute SQL statements.

This is a sample PostgreSQL extension to test SPI (Server Programming Interface) SQL execution in Zig. The extension provides a number of methods used by the test suite to verify that SPI access if functional.

## Testing

The extension uses PostgreSQL regression testing suite, which calls some of the exported functions in the extension itself.

The extension sets up a sample table with entries that are used by the tests.

```
zig build -freference-trace -p $PG_HOME
```

Run regression tests:

```
zig build -freference-trace -p $PG_HOME pg_regress
```
