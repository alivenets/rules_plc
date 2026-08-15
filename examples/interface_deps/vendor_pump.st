(* Vendor-supplied interface. In production this file would ship from
an upstream vendor Bazel module carrying only {external}
declarations of the POUs the vendor's runtime provides -- never
their bodies. plc emits an extern declaration for the FB (plus its
struct layout in the generated headers) and skips code generation
for its body.

    The body is supplied here by vendor_pump_stub.cc through cc_deps,
    for local exercise under the locally-installed plc without any
        real vendor runtime.

        In the source-bucket model, this st_library IS "vendor territory":
        consumers pull it in through `interface_deps`, so its
        `vendor_pump.st` sits in StInfo.compilation_context.interface_sources
    (visible to plc's `-i` at compile time for cross-library type
        resolution, never uploaded to the remote plc, which already has the
        vendor's real impl). *)

        {external}
        FUNCTION_BLOCK Pump
            VAR_INPUT
                rIn : REAL;
            END_VAR
            VAR_OUTPUT
                rOut : REAL;
            END_VAR
        END_FUNCTION_BLOCK
