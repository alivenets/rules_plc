(* Production code -- calls Pump from vendor_pump.st via
interface_deps, so vendor_pump.st is visible to plc's `-i` at
compile time (for cross-library type resolution) but does NOT ride
along in the exported StInfo.compilation_context.sources bucket
(see examples/interface_deps/remote_manifest.bzl). *)

FUNCTION_BLOCK Plant
    VAR_INPUT
        rIn : REAL;
    END_VAR
    VAR_OUTPUT
        rOut : REAL;
    END_VAR
    VAR
        pump : Pump;
    END_VAR
    pump(rIn := rIn);
    rOut := pump.rOut;
END_FUNCTION_BLOCK
