(*
Example library: defines a FUNCTION_BLOCK `Incrementer` that stores a
counter and places an integer at a direct address. This demonstrates
an st_library providing a reusable function block.
*)

FUNCTION_BLOCK Incrementer
    VAR
        Counter : INT := 0;
        Addr AT %QX0.0.1.0 : INT; (* direct address example *)
    END_VAR
    Counter := Counter + 1;
END_FUNCTION_BLOCK
