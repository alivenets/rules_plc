PROGRAM app_bin
    VAR
        my_link: link_handle;
        eth_st: eth_status;
        sender: net_send;
    END_VAR

    eth_st(link := my_link);
    IF eth_st.connected THEN
        sender(link := my_link, payload := 42);
    END_IF;
END_PROGRAM
