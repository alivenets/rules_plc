#include "library_deps_stubs/eth_headers_st/eth.h"
#include "library_deps_stubs/link_types_headers_st/link_types.h"
#include "library_deps_stubs/net_headers_st/net.h"

#include "gtest/gtest.h"

// `all_stubs` is a single `st_library_stub` built from the `all_libs`
// facade -- rules_plc walks that facade's transitive dep chain
// (link_types <- eth <- net) and emits one weak-symbol .c per underlying
// library, so linking against `all_stubs` alone satisfies every
// `{external}` symbol in the chain. Every stub is a no-op that leaves
// its output fields at whatever the caller zero-initialised them to.

TEST(FacadeStubs, EthStatusIsANoOp) {
    link_handle link = {};
    eth_status_type s = {};
    s.link = &link;
    eth_status(&s);
    EXPECT_FALSE(s.connected);
    EXPECT_EQ(s.speed_mbps, 0);
}

TEST(FacadeStubs, EthResetIsANoOp) {
    link_handle link = {};
    eth_reset_type r = {};
    r.link = &link;
    eth_reset(&r);
    EXPECT_FALSE(r.done);
}

TEST(FacadeStubs, NetSendIsANoOp) {
    link_handle link = {};
    net_send_type n = {};
    n.link = &link;
    n.payload = 123;
    net_send(&n);
    EXPECT_FALSE(n.ok);
}
