#include <cstdint>

#include "gtest/gtest.h"

extern "C" int32_t fast_double(int32_t x);

TEST(FastMath, DoublesItsInput) {
    EXPECT_EQ(fast_double(21), 42);
}
