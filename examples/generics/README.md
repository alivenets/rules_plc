# generics

`ANY`/`ANY_DUT`: type-erased `VAR_INPUT` parameters (an untyped pointer, no
runtime type tag), reinterpreted inside the `FUNCTION` as a known concrete
type. See `generics.st` for the mechanics.

`Generics.AnyStringReinterpretsTheErasedPointerAsItsKnownConcreteType`: plc's
`STRING` is a fixed-size char buffer, so a plain C string works. Unlike
`AnyIntValue`/`AnyNumValue`, `AnyStringValue` itself holds a pointer (to the
char data), not the data inline, so `first_char_via_any_string` -- which
reinterprets its argument as pointing directly at char data -- is passed
`v.string_`, not `&v`.
