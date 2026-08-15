(* {external} FUNCTION_BLOCK declared here; the body is provided by
   mid.cc as a native C++ definition. plc emits only an extern
   declaration for EXT_FB and skips code generation for its body. *)

{external}
FUNCTION_BLOCK EXT_FB
        VAR_INPUT
                rIn: REAL;
        END_VAR
        VAR_OUTPUT
                rOut: REAL;
        END_VAR
        VAR
                base: BASE_FB;
        END_VAR
END_FUNCTION_BLOCK
