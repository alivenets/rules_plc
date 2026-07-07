FUNCTION main : DINT
    IF top_value() <> 3 THEN
        main := 1;
        RETURN;
    END_IF
    main := 0;
END_FUNCTION
