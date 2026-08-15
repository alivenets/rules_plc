(* Top-of-chain library: depends on eth, which depends on link_types.
Its own generated `dependencies.plc.h` re-exports eth's headers by
relative path, and eth's `dependencies.plc.h` in turn re-exports
link_types' headers -- so the `link_handle` type used by-value in
net_send's VAR_IN_OUT resolves along the transitive chain. *)

{external}
FUNCTION_BLOCK net_send
    VAR_IN_OUT
        link: link_handle;
    END_VAR
    VAR_INPUT
        payload: DINT := 0;
    END_VAR
    VAR_OUTPUT
        ok: BOOL := FALSE;
    END_VAR
END_FUNCTION_BLOCK
