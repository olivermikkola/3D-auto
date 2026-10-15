/* What wasi-libc leaves out and Lua's io and os libraries still name.
   In a browser there are no temporary files and no shell: both fail. */
#include <errno.h>
#include <stdio.h>

FILE *tmpfile(void) { errno = ENOTSUP; return NULL; }
int system(const char *command) { return command ? -1 : 0; }
