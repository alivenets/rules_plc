#include "examples/simple_2/mathlib_headers_st/mathlib.h"
#include "gtest/gtest.h"

TEST(MathLib, AddsAndCountsCalls) {
    st_add_type inst;
    EXPECT_EQ(st_add(&inst, 10, 20), 30);
    EXPECT_EQ(call_count, 2);
}

TEST(Doubler, DoublesItsInput) {
    EXPECT_EQ(st_double(21), 42);
}
