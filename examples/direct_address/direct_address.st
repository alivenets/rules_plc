(*
Example program: instantiates `Incrementer` from the library, increments
its counter, and stores the result in a local variable. This file is the
`PROGRAM` entrypoint used by `st_binary`.
*)

PROGRAM direct_address
    VAR
        fb : Incrementer;
        out : INT;
    END_VAR
    fb();
END_PROGRAM
