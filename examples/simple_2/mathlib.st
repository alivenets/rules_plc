FUNCTION_BLOCK st_add
VAR_INPUT
    a : DINT;
    b : DINT;
END_VAR
VAR_OUTPUT
    out: DINT;
END_VAR
VAR
    call_count : DINT;
END_VAR
    call_count := call_count + 1;
    out := a + b;
END_FUNCTION_BLOCK

FUNCTION st_double : DINT
VAR_INPUT
    x : DINT;
END_VAR
    st_double := x * 2;
END_FUNCTION
