# external_c_library

`fast_math.st` declares `fast_double`, `fast_negate`, and `fast_counter` as
`{external}`: no ST implementation, just the signature, and (deliberately,
in this example) no native implementation linked in either. `fast_counter`
is a `FUNCTION_BLOCK`, demonstrating the weak-stub mechanism also works for
the struct-plus-function ABI `FUNCTION_BLOCK` compiles to, not just plain
value-returning `FUNCTION`s.

`fast_math_stubs` is a `__attribute__((weak))` `fast_double(int32_t)`/
`fast_negate(int32_t)` `:= 0` stub, generated from `fast_math`'s `{external}`
declarations (see `st_library_stub`). With no real implementation linked
anywhere, `fast_math_test.cc` exercises the stub fallback directly: both
functions return `0`, and `fast_counter`'s stub (void-returning, so no zero
value to return) is a no-op instead -- `value` is left exactly as the caller
set it, even across repeated calls that a real implementation would
accumulate into.
