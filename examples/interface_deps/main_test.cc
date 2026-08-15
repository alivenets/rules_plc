#include <array>
#include <cstdio>
#include <memory>
#include <string>

#include "interface_deps/plant_headers_st/plant.h"
#include "interface_deps/vendor_pump_headers_st/vendor_pump.h"
#include "tools/cpp/runfiles/runfiles.h"
#include "gtest/gtest.h"

using bazel::tools::cpp::runfiles::Runfiles;

// Direct-invocation coverage of the interface_deps split: Plant (the
// production FB, from plant.st) instantiates Pump (the vendor FB from
// vendor_pump.st, declared {external}) and forwards rIn through it.
// The generated plant.h + vendor_pump.h headers arrive via the fused
// st_library target's CcInfo -- for :plant that path stays open
// because interface_deps still forwards StTransitiveHeadersInfo
// bundles into the exported CcInfo, so a cc_test still gets the
// vendor's headers just as if it were a regular dep.
TEST(Plant, DoublesInputThroughVendorPump) {
    Plant_type inst{};
    inst.rIn = 21.0f;
    Plant(&inst);
    EXPECT_FLOAT_EQ(inst.rOut, 42.0f);
}

// End-to-end: st_binary links :plant (vendor_pump reached via
// interface_deps -- its object does NOT ride into the link from the ST
// side) with :vendor_pump_stub (native impl of Pump reached through
// cc_deps -- its object AND vendor_pump's compiled ctor object ride in
// through cc_library's own transitive CcInfo). Running the binary
// through runfiles confirms the two paths combine cleanly and the
// generated FUNCTION main wrapper exits without diagnostics.
TEST(InterfaceDepsMain, RunsAndExitsCleanly) {
    std::string error;
    std::unique_ptr<Runfiles> runfiles(Runfiles::CreateForTest(&error));
    ASSERT_NE(runfiles, nullptr) << error;

    std::string binary_path = runfiles->Rlocation("_main/interface_deps/main");
    FILE *pipe = popen((binary_path + " 2>&1").c_str(), "r");
    ASSERT_NE(pipe, nullptr);

    std::string output;
    std::array<char, 256> buffer;
    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        output += buffer.data();
    }
    EXPECT_EQ(pclose(pipe), 0) << output;
}
