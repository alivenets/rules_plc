VAR_GLOBAL
    call_count : DINT;
END_VAR

FUNCTION st_add : DINT
VAR_INPUT
    a : DINT;
    b : DINT;
END_VAR
    call_count := call_count + 1;
    st_add := a + b;
END_FUNCTION
