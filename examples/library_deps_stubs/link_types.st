(* Shared TYPE library at the bottom of a three-level dep chain.
Both eth and net take a `link_handle` by VAR_IN_OUT, so every library
downstream in the chain must see this struct definition -- exercising
rules_plc's relative-path `dependencies.plc.h` include chain. *)
TYPE

    link_handle:
STRUCT
    id: DINT := 0;
    state: DINT := 0;
END_STRUCT;

END_TYPE
