#include <postgres.h>
#include <libpq-fe.h>
#include <libpq/libpq-be-fe-helpers.h>

#include "include/libpqsrv.h"

void pqsrv_connect_prepare(void) {
    libpqsrv_connect_prepare();
}

void *pqsrv_connect(const char *conninfo, uint32 wait_event_info) {
    return libpqsrv_connect(conninfo, wait_event_info);
}

void*
pqsrv_connect_params(const char *const *keywords,
						const char *const *values,
						int expand_dbname,
						uint32 wait_event_info)
{
    return libpqsrv_connect_params(keywords, values, expand_dbname, wait_event_info);
}

void
pqsrv_disconnect(void *conn)  {
    libpqsrv_disconnect(conn);
}
