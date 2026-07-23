{external}
FUNCTION puts : DINT
VAR_INPUT {ref}
    text : STRING;
END_VAR
END_FUNCTION

PROGRAM hello
VAR
    x: DINT;
END_VAR
    x := doubler(x);
    puts('hello from rules_plc!$N');
END_PROGRAM
