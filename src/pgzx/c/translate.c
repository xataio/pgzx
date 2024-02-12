// DO NOT COMPILE 
//
// zig translate-c input file
//
// Use this file to manually translate some postgres headers to zig so we can copy and fix symbols that zig could not handle correctly.
//
// Run this command to generate the zig file:
//
//   $ zig translate-c -I $(pg_config --includedir-server) translate.c > translated.zig


#include <postgres.h>
#include <fmgr.h>
#include <varatt.h>


