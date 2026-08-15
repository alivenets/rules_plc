#include <array>
#include <cstdio>
#include <memory>
#include <string>

#include "st_c_implementation/mid_headers_st/mid.h"
#include "tools/cpp/runfiles/runfiles.h"
#include "gtest/gtest.h"

using bazel::tools::cpp::runfiles::Runfiles;

// BASE_FB is defined entirely in base.st -- its body runs the
// plc-generated code. Calling the generated wrapper against a
// zero-initialised instance exercises the ST assignment
// `xDone := xTrigger`.
TEST(BaseFb, PropagatesTriggerToDone) {
    BASE_FB_type inst{};
    inst.xTrigger = true;
    BASE_FB(&inst);
    EXPECT_TRUE(inst.xDone);
}

// EXT_FB is declared `{external}` in mid.st; the body lives in mid.cc.
// Linking against :mid_cc (which supplies that body) plus :mid (which
// supplies the plc-generated struct layout and extern declaration) is
// enough for the test binary to invoke the native implementation
// directly.
TEST(ExtFb, InvokesNativeCppBody) {
    EXT_FB_type inst{};
    inst.rIn = 21.0f;
    EXT_FB(&inst);
    EXPECT_FLOAT_EQ(inst.rOut, 42.0f);
}

// End-to-end: the st_binary target links the plc-compiled main_program
// with the ST-generated BASE_FB body and the native EXT_FB body from
// mid.cc. Running the binary through runfiles confirms the two link
// paths (ST-compiled object + cc_library object) coexist without
// duplicate-symbol errors and the generated FUNCTION main wrapper exits
// cleanly.
TEST(MainBinary, RunsAndExitsCleanly) {
    std::string error;
    std::unique_ptr<Runfiles> runfiles(Runfiles::CreateForTest(&error));
    ASSERT_NE(runfiles, nullptr) << error;

    std::string binary_path =
        runfiles->Rlocation("_main/st_c_implementation/main");
    FILE* pipe = popen((binary_path + " 2>&1").c_str(), "r");
    ASSERT_NE(pipe, nullptr);

    std::string output;
    std::array<char, 256> buffer;
    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        output += buffer.data();
    }
    EXPECT_EQ(pclose(pipe), 0) << output;
}
