#include "examples/binary/hello_headers_st/doubler.h"
#include "gtest/gtest.h"

TEST(Hello, DoublesItsInput) {
    EXPECT_EQ(doubler(21), 42);
}
