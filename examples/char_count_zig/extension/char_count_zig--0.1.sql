\echo Use "CREATE EXTENSION char_count" to load this file. \quit
CREATE FUNCTION char_count_zig(TEXT, TEXT) RETURNS INTEGER
AS '$libdir/char_count_zig'
LANGUAGE C IMMUTABLE

