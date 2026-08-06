#include "simple_2/mathlib_headers_st/mathlib.h"
#include "gtest/gtest.h"

TEST(MathLib, AddsAndCountsCalls) {
    st_add_type inst{};
    inst.a = 10;
    inst.b = 20;
    st_add(&inst);
    EXPECT_EQ(inst.out, 30);
    st_add(&inst);
    EXPECT_EQ(inst.call_count, 2);
}

TEST(Doubler, DoublesItsInput) { EXPECT_EQ(st_double(21), 42); }
