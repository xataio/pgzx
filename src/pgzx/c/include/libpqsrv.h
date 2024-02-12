#ifndef PGZX_PQSRV_HELPERS
#define PGZX_PQSRV_HELPERS

#include <stdint.h>

// re-export the `libpqsrv` helper functions.
// The original functions use C-inline code, but unfortunately the translated
// zig code does not compile. We just wrap and reexport the functions that we need.

void pqsrv_connect_prepare(void);

void *pqsrv_connect(const char *conninfo, uint32_t wait_event_info);

void*
pqsrv_connect_params(const char *const *keywords,
						const char *const *values,
						int expand_dbname,
						uint32_t wait_event_info);

void
pqsrv_disconnect(void *conn);

void *
pqsrv_exec(void *conn, const char *query, uint32_t wait_event_info);

void *
pqsrv_exec_params(void *conn,
					 const char *command,
					 int nParams,
					 const void *paramTypes,
					 const char *const *paramValues,
					 const int *paramLengths,
					 const int *paramFormats,
					 int resultFormat,
					 uint32 wait_event_info);

#endif
