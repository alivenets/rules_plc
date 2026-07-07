FUNCTION main : DINT
    IF fast_double(21) <> 42 THEN
        main := 1;
        RETURN;
    END_IF
    main := 0;
END_FUNCTION
