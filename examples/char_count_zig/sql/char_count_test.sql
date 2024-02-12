CREATE EXTENSION char_count_zig;

SELECT char_count_zig('aaabccd', 'a');
SELECT char_count_zig('aaabccd', 'b');
SELECT char_count_zig('aaabccd', 'c');
SELECT char_count_zig('aaabccd', 'd');
SELECT char_count_zig('aaabccd', 'e');
SELECT char_count_zig('aaabccd', 'abc');
SELECT char_count_zig('aaabccd', NULL);
SELECT char_count_zig(NULL, 'a');
SELECT char_count_zig(NULL, NULL);
