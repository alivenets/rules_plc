FUNCTION_BLOCK st_counter
VAR_INPUT
    step : DINT;
END_VAR
VAR_OUTPUT
    value : DINT;
END_VAR
    value := value + step;
END_FUNCTION_BLOCK
