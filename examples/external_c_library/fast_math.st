{external}
FUNCTION fast_double : DINT
    VAR_INPUT
        x : DINT;
    END_VAR
END_FUNCTION

{external}
FUNCTION fast_negate : DINT
    VAR_INPUT
        x : DINT;
    END_VAR
END_FUNCTION

(* A stateful {external} FUNCTION_BLOCK, unlike fast_double/fast_negate above
-- exercises the same weak-stub mechanism for the struct-plus-function ABI
FUNCTION_BLOCK compiles to, rather than a plain value-returning function. 
*)
{external}
FUNCTION_BLOCK fast_counter
    VAR_INPUT
        step : DINT;
    END_VAR
    VAR
        state: DINT;
    END_VAR
    VAR_OUTPUT
        value : DINT;
    END_VAR
END_FUNCTION_BLOCK
