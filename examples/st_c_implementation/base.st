FUNCTION_BLOCK BASE_FB
        VAR_INPUT
                xTrigger: BOOL;
        END_VAR
        VAR_OUTPUT
                xDone: BOOL;
        END_VAR

xDone := xTrigger;

END_FUNCTION_BLOCK
