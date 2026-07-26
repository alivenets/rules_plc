// point_lib.h references Coordinate but doesn't #include point_types.h
// itself (plc's header template doesn't track cross-header type deps) --
// dependencies.plc.h (which every generated header #includes unconditionally
// as its own first include) pulls in point_types.h automatically instead,
// since it's one of point_lib's own hdrs (see st/private/generate_headers.py).
#include "tests/point_lib_headers_st/point_lib.h"

#include "gtest/gtest.h"

TEST(Hdrs, MakePointUsesDutTypeAcrossCompileUnits) {
    EXPECT_EQ(make_point(4, 6), 10);
}
