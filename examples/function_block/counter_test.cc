#include <cstdint>

#include "gtest/gtest.h"

// Layout matches st_counter's compiled instance struct: vtable pointer,
// then VAR_INPUT/VAR_OUTPUT fields in declaration order. st_counter's body
// never dereferences the vtable slot, so it's left zeroed here.
struct StCounter {
    void *vtable;
    int32_t step;
    int32_t value;
};

extern "C" void st_counter(StCounter *self);

TEST(Counter, AccumulatesStepsAcrossCalls) {
    StCounter c = {};
    c.step = 3;
    st_counter(&c);
    c.step = 4;
    st_counter(&c);
    EXPECT_EQ(c.value, 7);
}
