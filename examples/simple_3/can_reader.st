
FUNCTION_BLOCK CAN_READER
    VAR
        buffer: CAN_MSG_BUFFER;
    END_VAR
    VAR_IN_OUT
        out_msg: CAN_MSG;
    END_VAR

    buffer.byte1 := buffer.byte1 + 1;

    out_msg.value_byte := buffer.byte1;

END_FUNCTION_BLOCK
