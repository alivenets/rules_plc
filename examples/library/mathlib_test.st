FUNCTION main : DINT
VAR_EXTERNAL
    call_count : DINT;
END_VAR
    IF st_add(2, 3) <> 5 THEN
        main := 1;
        RETURN;
    END_IF
    IF st_add(10, 20) <> 30 THEN
        main := 1;
        RETURN;
    END_IF
    IF call_count <> 2 THEN
        main := 1;
        RETURN;
    END_IF
    main := 0;
END_FUNCTION
