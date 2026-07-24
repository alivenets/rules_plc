#include "examples/library/mathlib_st/mathlib.h"
#include "gtest/gtest.h"

TEST(MathLib, AddsAndCountsCalls) {
    EXPECT_EQ(st_add(2, 3), 5);
    EXPECT_EQ(st_add(10, 20), 30);
    EXPECT_EQ(call_count, 2);
}
