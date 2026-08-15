(* Middle-of-chain library: depends on link_types, so its generated
`dependencies.plc.h` re-exports link_types' headers by relative path. Every
FB here is `{external}` -- no ST implementation, so the C-level symbols
are supplied by whatever links against this library. *)

{external}
FUNCTION_BLOCK eth_status
    VAR_IN_OUT
        link: link_handle;
    END_VAR
    VAR_OUTPUT
        connected: BOOL := FALSE;
        speed_mbps: DINT := 0;
    END_VAR
END_FUNCTION_BLOCK

{external}
FUNCTION_BLOCK eth_reset
    VAR_IN_OUT
        link: link_handle;
    END_VAR
    VAR_OUTPUT
        done: BOOL := FALSE;
    END_VAR
END_FUNCTION_BLOCK
