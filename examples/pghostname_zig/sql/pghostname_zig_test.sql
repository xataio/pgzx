CREATE EXTENSION pghostname_zig;

SELECT COALESCE(length(pghostname_zig()), 0) > 0;
