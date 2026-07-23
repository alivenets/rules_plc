#include <cstdint>

#include "gtest/gtest.h"

extern "C" int32_t make_point(int32_t x, int32_t y);

TEST(Hdrs, MakePointUsesDutTypeAcrossCompileUnits) {
    EXPECT_EQ(make_point(4, 6), 10);
}
