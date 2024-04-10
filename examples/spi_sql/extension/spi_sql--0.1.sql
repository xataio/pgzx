CREATE TABLE tbl (
    id serial not null primary key,
    value text
);

INSERT INTO tbl (id, value) VALUES
  (0, 'Hello'),
  (1, 'World')
;

CREATE FUNCTION query_by_id(int4) RETURNS TEXT
AS '$libdir/spi_sql' LANGUAGE C VOLATILE;

CREATE FUNCTION query_by_value(TEXT) RETURNS INT4
AS '$libdir/spi_sql' LANGUAGE C VOLATILE;

CREATE FUNCTION ins_value(INT4, TEXT) RETURNS INT4
AS '$libdir/spi_sql' LANGUAGE C VOLATILE;

CREATE FUNCTION test_iter() RETURNS VOID
AS '$libdir/spi_sql' LANGUAGE C VOLATILE;

CREATE FUNCTION test_rows_of() RETURNS VOID
AS '$libdir/spi_sql' LANGUAGE C VOLATILE;
