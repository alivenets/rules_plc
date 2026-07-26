FUNCTION_BLOCK st_add : DINT
VAR_INPUT
    a : DINT;
    b : DINT;
END_VAR
VAR
    call_count : DINT;
END_VAR
    call_count := call_count + 1;
    st_add := a + b;
END_FUNCTION

FUNCTION st_double : DINT
VAR_INPUT
    x : DINT;
END_VAR
    st_double := x * 2;
END_FUNCTION
