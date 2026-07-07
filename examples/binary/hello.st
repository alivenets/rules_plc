{external}
FUNCTION puts : DINT
VAR_INPUT {ref}
    text : STRING;
END_VAR
END_FUNCTION

PROGRAM hello
    puts('hello from rules_plc!$N');
END_PROGRAM
