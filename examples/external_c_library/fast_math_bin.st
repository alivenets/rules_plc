PROGRAM fast_math_bin
    VAR
        a : REAL := 12.5;
        b : REAL := 3.5;
        sum : REAL;
        diff : REAL;
        prod : REAL;
        quot : REAL;
        valid_div : BOOL;
    END_VAR

    sum := a + b;
    diff := a - b;
    prod := a * b;

    valid_div := b <> 0.0;
    IF valid_div THEN
        quot := a / b;
    ELSE
        quot := 0.0;
    END_IF;

END_PROGRAM
