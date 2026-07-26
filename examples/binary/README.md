# binary

A standalone `st_binary` with no library dependencies. `st_binary` bundles
plc's generated C headers for its own `srcs`/`hdrs` the same way `st_library`
does, so `hello_test.cc` can `#include` them directly.
