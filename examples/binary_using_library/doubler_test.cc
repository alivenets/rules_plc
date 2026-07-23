#include <cstdint>

#include "gtest/gtest.h"

extern "C" int32_t st_double(int32_t x);

TEST(Doubler, DoublesItsInput) {
    EXPECT_EQ(st_double(21), 42);
}
