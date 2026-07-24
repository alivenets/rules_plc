#include "examples/binary_using_library/doubler_st/doubler.h"
#include "gtest/gtest.h"

TEST(Doubler, DoublesItsInput) {
    EXPECT_EQ(st_double(21), 42);
}
