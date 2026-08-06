#include "function_block/counter_headers_st/counter.h"
#include "gtest/gtest.h"

TEST(Counter, AccumulatesStepsAcrossCalls) {
    st_counter_type c = {};
    c.step = 3;
    st_counter(&c);
    c.step = 4;
    st_counter(&c);
    EXPECT_EQ(c.value, 7);
}
