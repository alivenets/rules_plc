// Every ANY_*-typed VAR_INPUT parameter below is compiled to an untyped
// pointer (POINTER TO __VOID at the type-system level -- see
// third_party/rusty/support-generic-data-types.patch, which added ANY_DUT,
// ANY_SIMPLE, ANY_INT, ANY_STRING and ANY_DATE as usable types). There's no
// runtime type tag, so the callee has to already know (by convention) what
// concrete type it's been handed, and reinterprets the erased pointer via
// an ordinary POINTER TO <ConcreteType> local before dereferencing it.
//
// Callers must pass an explicit REF(x): unlike VAR_IN_OUT, ANY_* types
// aren't auto-referenced at the call site.
//
// The specific nature (NUM/INT/REAL/DUT/...) does NOT restrict what a
// caller may pass here, despite what the IEC 61131-3 nature hierarchy
// implies: plc only enforces a nature when it's bound to a generic type
// parameter (`FUNCTION foo<T : ANY_INT>`, not used in this file -- see
// validate_assignment_mismatch's `is_void_pointer` bypass in the same
// patch, which skips type checking uniformly for every ANY_* type). Below,
// the nature is chosen only to document each function's intent to callers;
// it isn't enforced by the compiler.
//
// ANY_* types may only be used as VAR_INPUT here, never as a return type
// (there's no concrete type for a caller to reconstitute one from) or as
// VAR_IN_OUT (that combination currently segfaults in plc: VAR_IN_OUT's own
// implicit auto-deref double-dereferences the already-erased pointer).

TYPE Point : STRUCT
    x : DINT;
    y : DINT;
END_STRUCT END_TYPE

// ANY accepts any type at all; the callee must already know (here, always
// DINT) what it's been handed.
FUNCTION double_via_any : DINT
VAR_INPUT
    val : ANY;
END_VAR
VAR
    concrete : POINTER TO DINT;
END_VAR
    concrete := val;
    double_via_any := concrete^ * 2;
END_FUNCTION

// ANY_DUT: intended for derived types (STRUCT/ENUM/ALIAS).
FUNCTION point_sum : DINT
VAR_INPUT
    val : ANY_DUT;
END_VAR
VAR
    concrete : POINTER TO Point;
END_VAR
    concrete := val;
    point_sum := concrete^.x + concrete^.y;
END_FUNCTION

// ANY_NUM: intended for any numeric type (integer or real). Reinterpreted
// here as DINT.
FUNCTION num_via_any_num : DINT
VAR_INPUT
    val : ANY_NUM;
END_VAR
VAR
    concrete : POINTER TO DINT;
END_VAR
    concrete := val;
    num_via_any_num := concrete^;
END_FUNCTION

// ANY_INT: intended for integer types.
FUNCTION int_via_any_int : DINT
VAR_INPUT
    val : ANY_INT;
END_VAR
VAR
    concrete : POINTER TO DINT;
END_VAR
    concrete := val;
    int_via_any_int := concrete^;
END_FUNCTION

// ANY_REAL: intended for floating-point types.
FUNCTION real_via_any_real : REAL
VAR_INPUT
    val : ANY_REAL;
END_VAR
VAR
    concrete : POINTER TO REAL;
END_VAR
    concrete := val;
    real_via_any_real := concrete^;
END_FUNCTION

// ANY_STRING: intended for STRING/WSTRING. Reinterpreted here as POINTER TO
// CHAR to read just the first character: STRING isn't array-indexable, and
// comparing whole STRING values needs the stdlib's STRING_EQUAL, which
// isn't linked into this example.
FUNCTION first_char_via_any_string : CHAR
VAR_INPUT
    val : ANY_STRING;
END_VAR
VAR
    concrete : POINTER TO CHAR;
END_VAR
    concrete := val;
    first_char_via_any_string := concrete^;
END_FUNCTION
