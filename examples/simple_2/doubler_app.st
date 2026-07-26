{external}
FUNCTION puts : DINT
VAR_INPUT {ref}
    text : STRING;
END_VAR
END_FUNCTION

PROGRAM doubler_app
VAR
    result : DINT;
END_VAR
    result := st_double(21);
    puts('doubled value computed$N');
END_PROGRAM
