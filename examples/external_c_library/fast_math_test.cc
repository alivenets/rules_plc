#include <cstdint>

#include "gtest/gtest.h"

// fast_double is declared {external} in fast_math.st (no ST body of its
// own), so plc's header generator doesn't emit a header for it at all --
// this tests fast_math_c, the native implementation, directly.
extern "C" int32_t fast_double(int32_t x);

TEST(FastMath, DoublesItsInput) {
    EXPECT_EQ(fast_double(21), 42);
}
