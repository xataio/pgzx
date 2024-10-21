\echo Use "CREATE EXTENSION pghostname_zig" to load this file. \quit
CREATE FUNCTION pghostname_zig() RETURNS TEXT
AS '$libdir/pghostname_zig'
LANGUAGE C IMMUTABLE;