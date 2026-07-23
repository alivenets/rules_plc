#include <cstdint>

#include "gtest/gtest.h"

extern "C" {
int32_t st_add(int32_t a, int32_t b);
extern int32_t call_count;
}

TEST(MathLib, AddsAndCountsCalls) {
    EXPECT_EQ(st_add(2, 3), 5);
    EXPECT_EQ(st_add(10, 20), 30);
    EXPECT_EQ(call_count, 2);
}
