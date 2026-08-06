#include "tests/top_headers_st/top.h"
#include "gtest/gtest.h"

TEST(TransitiveDeps, LinksSymbolsFromEveryLevel) { EXPECT_EQ(top_value(), 3); }
