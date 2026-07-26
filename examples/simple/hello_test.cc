#include <array>
#include <cstdio>
#include <memory>
#include <string>

#include "gtest/gtest.h"
#include "tools/cpp/runfiles/runfiles.h"

using bazel::tools::cpp::runfiles::Runfiles;

// Runs the actual "hello" executable and captures its stdout, exercising
// the generated FUNCTION main entry point and hello's {external} puts
// binding end to end.
TEST(Hello, PrintsGreetingWhenRun) {
    std::string error;
    std::unique_ptr<Runfiles> runfiles(Runfiles::CreateForTest(&error));
    ASSERT_NE(runfiles, nullptr) << error;

    std::string hello_path = runfiles->Rlocation("_main/examples/simple/hello");
    FILE* pipe = popen((hello_path + " 2>&1").c_str(), "r");
    ASSERT_NE(pipe, nullptr);

    std::string output;
    std::array<char, 256> buffer;
    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        output += buffer.data();
    }
    ASSERT_EQ(pclose(pipe), 0);

    EXPECT_NE(output.find("hello from rules_plc!"), std::string::npos) << output;
}
