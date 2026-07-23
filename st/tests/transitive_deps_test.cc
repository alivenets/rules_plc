#include <cstdint>

#include "gtest/gtest.h"

extern "C" int32_t top_value(void);

TEST(TransitiveDeps, LinksSymbolsFromEveryLevel) {
    EXPECT_EQ(top_value(), 3);
}
