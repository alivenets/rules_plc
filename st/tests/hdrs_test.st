FUNCTION main : DINT
VAR
    x : Coordinate;
    y : Coordinate;
END_VAR
    x := 4;
    y := 6;
    IF make_point(x, y) <> 10 THEN
        main := 1;
        RETURN;
    END_IF
    main := 0;
END_FUNCTION
