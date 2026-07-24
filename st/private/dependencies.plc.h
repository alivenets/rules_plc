// Stub for plc-generated headers, which unconditionally #include this --
// and, since a single translation unit commonly #includes more than one
// module's .h (each pulling this file in via its own <dependencies.plc.h>),
// possibly more than once, hence the include guard below. Also declares
// convenience unions for reinterpreting an ANY_*-typed `void*` parameter
// (see typesystem.rs's ANY_* types -- all untyped pointers, with no runtime
// type tag, so caller and callee must already agree on the concrete type by
// convention) as a concrete value on the C/C++ side. One union per nature,
// matching what that nature's type actually accepts:
//   - AnyIntValue:    ANY_INT     (SINT/USINT/INT/UINT/DINT/UDINT/LINT/ULINT)
//   - AnyBitValue:    ANY_BIT     (BOOL/BYTE/WORD/DWORD/LWORD)
//   - AnyRealValue:   ANY_REAL    (REAL/LREAL)
//   - AnyStringValue: ANY_STRING  (STRING/WSTRING)
//   - AnyNumValue:    ANY_NUM     (every ANY_INT and ANY_REAL member)
// Copied byte-for-byte into every library's own headers dir (see
// st/private/generate_headers.sh), so it carries no library-specific
// declarations of its own.
//
// Every member name is suffixed with `_` (matching int_, which needs it to
// avoid the `int` keyword) so that all IEC 61131-3 type names are spelled
// consistently, regardless of which happen to collide with a C/C++ keyword.
//
// Define WITH_PLC_64BIT before including a library's headers to also get
// the 64-bit members (LINT/ULINT/LWORD/LREAL); omit it to build against
// targets without 64-bit support.

#ifndef DEPENDENCIES_PLC_H_
#define DEPENDENCIES_PLC_H_

#include <stdint.h>

typedef union {
    int8_t sint_;
    uint8_t usint_;
    int16_t int_;
    uint16_t uint_;
    int32_t dint_;
    uint32_t udint_;
#ifdef WITH_PLC_64BIT
    int64_t lint_;
    uint64_t ulint_;
#endif
} AnyIntValue;

typedef union {
    bool bit_;
    uint8_t byte_;
    uint16_t word_;
    uint32_t dword_;
#ifdef WITH_PLC_64BIT
    uint64_t lword_;
#endif
} AnyBitValue;

typedef union {
    float real_;
#ifdef WITH_PLC_64BIT
    double lreal_;
#endif
} AnyRealValue;

typedef union {
    char *string_;
    int16_t *wstring_;
} AnyStringValue;

typedef union {
    int8_t sint_;
    uint8_t usint_;
    int16_t int_;
    uint16_t uint_;
    int32_t dint_;
    uint32_t udint_;
#ifdef WITH_PLC_64BIT
    int64_t lint_;
    uint64_t ulint_;
#endif
    float real_;
#ifdef WITH_PLC_64BIT
    double lreal_;
#endif
} AnyNumValue;

#endif /* !DEPENDENCIES_PLC_H_ */
