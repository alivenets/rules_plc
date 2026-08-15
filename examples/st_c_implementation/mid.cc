#include "st_c_implementation/mid_headers_st/mid.h"

// Native implementation of EXT_FB, whose FUNCTION_BLOCK signature is
// declared as `{external}` in mid.st. plc emits only the extern
// declaration for EXT_FB and skips its body; this definition provides
// the actual runtime behavior that main_program invokes.
void EXT_FB(EXT_FB_type* self) {
    self->rOut = self->rIn * 2.0f;
}
