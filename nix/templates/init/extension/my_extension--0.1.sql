\echo Use "CREATE EXTENSION my_extension" to load this file. \quit
CREATE FUNCTION hello() RETURNS TEXT
AS '$libdir/my_extension'
LANGUAGE C IMMUTABLE

