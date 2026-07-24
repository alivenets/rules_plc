// point_lib.h references Coordinate but doesn't #include point_types.h
// itself (plc's header template doesn't track cross-header type deps), so
// consumers must include the type's own header first.
#include "tests/point_lib_st/point_types.h"
#include "tests/point_lib_st/point_lib.h"

#include "gtest/gtest.h"

TEST(Hdrs, MakePointUsesDutTypeAcrossCompileUnits) {
    EXPECT_EQ(make_point(4, 6), 10);
}
