# function_block

`counter`: a `FUNCTION_BLOCK` (stateful, instantiable POU) compiled as an
`st_library`, with a `cc_test` exercising an instance of it across multiple
calls.

`totalizer` embeds an `st_counter` instance as a `VAR`, delegating to it
rather than reimplementing accumulation -- exercises a `FUNCTION_BLOCK`
composed of another `FUNCTION_BLOCK`, both in the generated C header (a
nested struct field) and in the compiled ST (`deps` lets `totalizer.st -i
counter.st`, resolving the `st_counter` type).

`totalizer_test.cc` includes `counter.h` before `totalizer.h`: `totalizer`'s
own generated header doesn't `#include` `counter`'s header itself (plc's
header template doesn't track cross-header type deps -- see
`tests/hdrs_test.cc`), so `counter`'s header must be included first.

The embedded `st_counter` is an ordinary nested struct field, not an opaque
handle -- callable and inspectable directly, same as any standalone
`st_counter_type` instance (see `Totalizer.EmbeddedCounterIsAnOrdinaryNestedStructField`).
