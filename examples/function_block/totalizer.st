(* A FUNCTION_BLOCK composing another FUNCTION_BLOCK: st_totalizer embeds an
   st_counter instance as an ordinary VAR, delegating its own accumulation to
   it instead of reimplementing it. Demonstrates that plc's generated C
   struct for a FUNCTION_BLOCK nests an embedded FUNCTION_BLOCK's own
   generated struct as an ordinary field -- see totalizer_test.cc. *)
FUNCTION_BLOCK st_totalizer
VAR_INPUT
    amount : DINT;
END_VAR
VAR_OUTPUT
    total : DINT;
END_VAR
VAR
    accumulator : st_counter;
END_VAR
    accumulator(step := amount);
    total := accumulator.value;
END_FUNCTION_BLOCK
