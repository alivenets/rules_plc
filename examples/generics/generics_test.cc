#include "examples/generics/generics_st/generics.h"

#include "gtest/gtest.h"

TEST(Generics, AnyReinterpretsTheErasedPointerAsItsKnownConcreteType) {
    int32_t x = 21;
    EXPECT_EQ(double_via_any(&x), 42);
}

TEST(Generics, AnyDutReinterpretsTheErasedPointerAsItsKnownStructType) {
    Point p = {3, 4};
    EXPECT_EQ(point_sum(&p), 7);
}

TEST(Generics, AnyNumReinterpretsTheErasedPointerAsItsKnownConcreteType) {
    AnyNumValue v;
    v.dint_ = 5;
    EXPECT_EQ(num_via_any_num(&v), 5);
}

TEST(Generics, AnyIntReinterpretsTheErasedPointerAsItsKnownConcreteType) {
    AnyIntValue v;
    v.dint_ = 11;
    EXPECT_EQ(int_via_any_int(&v), 11);
}

TEST(Generics, AnyRealReinterpretsTheErasedPointerAsItsKnownConcreteType) {
    float x = 1.5f;
    EXPECT_FLOAT_EQ(real_via_any_real(&x), 1.5f);
}

TEST(Generics, AnyStringReinterpretsTheErasedPointerAsItsKnownConcreteType) {
    // plc's STRING is a fixed-size char buffer, so a plain C string works.
    // Unlike AnyIntValue/AnyNumValue above, AnyStringValue itself holds a
    // pointer (to the char data), not the data inline, so first_char_via_
    // any_string -- which reinterprets its argument as pointing directly at
    // char data -- is passed v.string_, not &v.
    char s[] = "hello";
    AnyStringValue v;
    v.string_ = s;
    EXPECT_EQ(first_char_via_any_string(v.string_), 'h');
}
