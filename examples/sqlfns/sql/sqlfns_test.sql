CREATE EXTENSION sqlfns;

SET search_path TO sqlfns;

SELECT hello_world_c(NULL);
SELECT hello_world_c('pgzx');

SELECT hello_world_zig(NULL);
SELECT hello_world_zig('pgzx');

SELECT hello_world_zig(NULL);
SELECT hello_world_zig('pgzx');

SELECT hello_world_zig_null(NULL);
SELECT hello_world_zig_null('pgzx');

SELECT hello_world_zig_datum(NULL);
SELECT hello_world_zig_datum('pgzx');

SELECT hello_world_anon(NULL);
SELECT hello_world_anon('pgzx');

SELECT hello_world_mod(NULL);
SELECT hello_world_mod('pgzx');

SELECT hello_world_file(NULL);
SELECT hello_world_file('pgzx');

DROP EXTENSION sqlfns;
