#include "function_block/counter_headers_st/counter.h"
#include "function_block/totalizer_headers_st/totalizer.h"

#include "gtest/gtest.h"

TEST(Totalizer, DelegatesAccumulationToEmbeddedCounter) {
    st_totalizer_type t = {};
    t.amount = 3;
    st_totalizer(&t);
    t.amount = 4;
    st_totalizer(&t);
    EXPECT_EQ(t.total, 7);
}

TEST(Totalizer, EmbeddedCounterIsAnOrdinaryNestedStructField) {
    st_totalizer_type t = {};
    t.accumulator.step = 5;
    st_counter(&t.accumulator);
    EXPECT_EQ(t.accumulator.value, 5);
    EXPECT_EQ(t.total, 0);
}
