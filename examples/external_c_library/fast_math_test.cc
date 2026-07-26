#include "examples/external_c_library/fast_math_headers_st/fast_math.h"

#include "gtest/gtest.h"

TEST(FastMathStub, ReturnsZeroWithoutARealImplementationLinked) {
    EXPECT_EQ(fast_double(21), 0);
    EXPECT_EQ(fast_negate(5), 0);
}

// fast_counter's weak stub is void-returning, so it has no zero value to
// return -- it's a no-op instead: value is left exactly as the caller set
// it, even across repeated calls that a real implementation would
// accumulate into.
TEST(FastMathStub, CounterDoesNothingWithoutARealImplementationLinked) {
    fast_counter_type c = {};
    c.step = 3;
    fast_counter(&c);
    c.step = 4;
    fast_counter(&c);
    EXPECT_EQ(c.value, 0);
}
