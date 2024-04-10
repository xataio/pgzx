CREATE EXTENSION spi_sql;

SELECT spi_sql.query_by_id(0); -- return 'Hello'
SELECT spi_sql.query_by_id(1); -- return 'World'
SELECT spi_sql.query_by_id(2); -- Fail

SELECT spi_sql.query_by_value('Hello'); -- return 0
SELECT spi_sql.query_by_value('World'); -- return 1
SELECT spi_sql.query_by_value('test'); -- FAIL

SELECT spi_sql.ins_value(2, 'test');
SELECT spi_sql.query_by_id(2); -- return 'test'
SELECT spi_sql.query_by_value('test'); -- return 2

SELECT spi_sql.test_iter();

SELECT spi_sql.test_rows_of();

DROP EXTENSION spi_sql;
