FUNCTION main : DINT
VAR
    c : st_counter;
END_VAR
    c(step := 3);
    c(step := 4);
    IF c.value = 7 THEN
        main := 0;
    ELSE
        main := 1;
    END_IF
END_FUNCTION
