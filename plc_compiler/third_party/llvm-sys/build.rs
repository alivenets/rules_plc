use std::env;

// This build.rs replaces llvm-sys's own (see crate.annotation in
// MODULE.bazel), which shells out to `llvm-config` to discover LLVM's
// install location, its component libraries, and their link flags (and,
// upstream, also compiles wrappers/target.c against `llvm-config --cflags`
// -- that instead happens as an ordinary cc_library, linked in via
// crate.annotation(link_deps = [...]); see BUILD.bazel). That's both
// unnecessary and actively harmful under Bazel: we always build against
// exactly one pinned LLVM (see MODULE.bazel's llvm.toolchain), so there's
// nothing to discover, and llvm-config resolves its own install location to
// an absolute, user/machine-specific Bazel output-base path at runtime --
// embedding that into rustc-link-search would break build determinism and
// isn't hermetic (it's reached by escaping outside anything Bazel declared
// as an input). Every value below was captured once from `llvm-config` for
// the pinned LLVM version (see MODULE.bazel) and is now hardcoded directly;
// if that version ever changes, regenerate them (`llvm-config --libnames
// --link-static`, `--system-libs --link-static`) and update this file to
// match.

/// Every LLVM component static library, in the exact order `llvm-config
/// --libnames --link-static` reports them. Order matters: these are linked
/// with a plain linker (no --start-group/--end-group), which only resolves
/// symbols against archives it hasn't already passed.
static LLVM_LIBS: &[&str] = &[
    "LLVMWindowsManifest",
    "LLVMXRay",
    "LLVMLibDriver",
    "LLVMDlltoolDriver",
    "LLVMTelemetry",
    "LLVMTextAPIBinaryReader",
    "LLVMCoverage",
    "LLVMLineEditor",
    "LLVMXCoreDisassembler",
    "LLVMXCoreCodeGen",
    "LLVMXCoreDesc",
    "LLVMXCoreInfo",
    "LLVMX86TargetMCA",
    "LLVMX86Disassembler",
    "LLVMX86AsmParser",
    "LLVMX86CodeGen",
    "LLVMX86Desc",
    "LLVMX86Info",
    "LLVMWebAssemblyDisassembler",
    "LLVMWebAssemblyAsmParser",
    "LLVMWebAssemblyCodeGen",
    "LLVMWebAssemblyUtils",
    "LLVMWebAssemblyDesc",
    "LLVMWebAssemblyInfo",
    "LLVMVEDisassembler",
    "LLVMVEAsmParser",
    "LLVMVECodeGen",
    "LLVMVEDesc",
    "LLVMVEInfo",
    "LLVMSystemZDisassembler",
    "LLVMSystemZAsmParser",
    "LLVMSystemZCodeGen",
    "LLVMSystemZDesc",
    "LLVMSystemZInfo",
    "LLVMSPIRVCodeGen",
    "LLVMSPIRVDesc",
    "LLVMSPIRVInfo",
    "LLVMSPIRVAnalysis",
    "LLVMSparcDisassembler",
    "LLVMSparcAsmParser",
    "LLVMSparcCodeGen",
    "LLVMSparcDesc",
    "LLVMSparcInfo",
    "LLVMRISCVTargetMCA",
    "LLVMRISCVDisassembler",
    "LLVMRISCVAsmParser",
    "LLVMRISCVCodeGen",
    "LLVMRISCVDesc",
    "LLVMRISCVInfo",
    "LLVMPowerPCDisassembler",
    "LLVMPowerPCAsmParser",
    "LLVMPowerPCCodeGen",
    "LLVMPowerPCDesc",
    "LLVMPowerPCInfo",
    "LLVMNVPTXCodeGen",
    "LLVMNVPTXDesc",
    "LLVMNVPTXInfo",
    "LLVMMSP430Disassembler",
    "LLVMMSP430AsmParser",
    "LLVMMSP430CodeGen",
    "LLVMMSP430Desc",
    "LLVMMSP430Info",
    "LLVMMipsDisassembler",
    "LLVMMipsAsmParser",
    "LLVMMipsCodeGen",
    "LLVMMipsDesc",
    "LLVMMipsInfo",
    "LLVMLoongArchDisassembler",
    "LLVMLoongArchAsmParser",
    "LLVMLoongArchCodeGen",
    "LLVMLoongArchDesc",
    "LLVMLoongArchInfo",
    "LLVMLanaiDisassembler",
    "LLVMLanaiCodeGen",
    "LLVMLanaiAsmParser",
    "LLVMLanaiDesc",
    "LLVMLanaiInfo",
    "LLVMHexagonDisassembler",
    "LLVMHexagonCodeGen",
    "LLVMHexagonAsmParser",
    "LLVMHexagonDesc",
    "LLVMHexagonInfo",
    "LLVMBPFDisassembler",
    "LLVMBPFAsmParser",
    "LLVMBPFCodeGen",
    "LLVMBPFDesc",
    "LLVMBPFInfo",
    "LLVMAVRDisassembler",
    "LLVMAVRAsmParser",
    "LLVMAVRCodeGen",
    "LLVMAVRDesc",
    "LLVMAVRInfo",
    "LLVMARMDisassembler",
    "LLVMARMAsmParser",
    "LLVMARMCodeGen",
    "LLVMARMDesc",
    "LLVMARMUtils",
    "LLVMARMInfo",
    "LLVMAMDGPUTargetMCA",
    "LLVMAMDGPUDisassembler",
    "LLVMAMDGPUAsmParser",
    "LLVMAMDGPUCodeGen",
    "LLVMAMDGPUDesc",
    "LLVMAMDGPUUtils",
    "LLVMAMDGPUInfo",
    "LLVMAArch64Disassembler",
    "LLVMAArch64AsmParser",
    "LLVMAArch64CodeGen",
    "LLVMAArch64Desc",
    "LLVMAArch64Utils",
    "LLVMAArch64Info",
    "LLVMOrcDebugging",
    "LLVMOrcJIT",
    "LLVMWindowsDriver",
    "LLVMMCJIT",
    "LLVMJITLink",
    "LLVMInterpreter",
    "LLVMExecutionEngine",
    "LLVMRuntimeDyld",
    "LLVMOrcTargetProcess",
    "LLVMOrcShared",
    "LLVMDWP",
    "LLVMDWARFCFIChecker",
    "LLVMDebugInfoLogicalView",
    "LLVMOption",
    "LLVMObjCopy",
    "LLVMMCA",
    "LLVMMCDisassembler",
    "LLVMLTO",
    "LLVMFrontendOpenACC",
    "LLVMFrontendHLSL",
    "LLVMFrontendDriver",
    "LLVMExtensions",
    "Polly",
    "PollyISL",
    "LLVMPasses",
    "LLVMHipStdPar",
    "LLVMCoroutines",
    "LLVMCFGuard",
    "LLVMipo",
    "LLVMInstrumentation",
    "LLVMVectorize",
    "LLVMSandboxIR",
    "LLVMLinker",
    "LLVMFrontendOpenMP",
    "LLVMFrontendDirective",
    "LLVMFrontendAtomic",
    "LLVMFrontendOffloading",
    "LLVMObjectYAML",
    "LLVMDWARFLinkerParallel",
    "LLVMDWARFLinkerClassic",
    "LLVMDWARFLinker",
    "LLVMGlobalISel",
    "LLVMMIRParser",
    "LLVMAsmPrinter",
    "LLVMSelectionDAG",
    "LLVMCodeGen",
    "LLVMTarget",
    "LLVMObjCARCOpts",
    "LLVMCodeGenTypes",
    "LLVMCGData",
    "LLVMIRPrinter",
    "LLVMInterfaceStub",
    "LLVMFileCheck",
    "LLVMFuzzMutate",
    "LLVMScalarOpts",
    "LLVMInstCombine",
    "LLVMAggressiveInstCombine",
    "LLVMTransformUtils",
    "LLVMBitWriter",
    "LLVMAnalysis",
    "LLVMProfileData",
    "LLVMSymbolize",
    "LLVMDebugInfoBTF",
    "LLVMDebugInfoPDB",
    "LLVMDebugInfoMSF",
    "LLVMDebugInfoCodeView",
    "LLVMDebugInfoGSYM",
    "LLVMDebugInfoDWARF",
    "LLVMDebugInfoDWARFLowLevel",
    "LLVMObject",
    "LLVMTextAPI",
    "LLVMMCParser",
    "LLVMIRReader",
    "LLVMAsmParser",
    "LLVMMC",
    "LLVMBitReader",
    "LLVMFuzzerCLI",
    "LLVMCore",
    "LLVMRemarks",
    "LLVMBitstreamReader",
    "LLVMBinaryFormat",
    "LLVMTargetParser",
    "LLVMTableGen",
    "LLVMSupport",
    "LLVMDemangle",
];

/// System (non-LLVM) dylibs `llvm-config --system-libs --link-static`
/// reports, plus the C++ standard library.
static SYSTEM_LIBS: &[&str] = &["rt", "dl", "m", "z", "zstd", "xml2", "stdc++"];

fn main() {
    println!("cargo:rerun-if-env-changed=LLVM_SYS_211_PREFIX");

    // Set by //third_party/llvm-sys:llvm_prefix (see BUILD.bazel), a
    // workspace-relative path (e.g. "external/toolchains_llvm++llvm+
    // llvm_toolchain_llvm") into the pinned LLVM toolchain -- deliberately
    // not machine-specific, unlike anything `llvm-config` would report.
    let prefix = env::var("LLVM_SYS_211_PREFIX")
        .expect("LLVM_SYS_211_PREFIX must be set (see //third_party/llvm-sys:BUILD.bazel)");

    let libdir = format!("{prefix}/lib");
    println!("cargo:libdir={libdir}"); // DEP_LLVM_LIBDIR
    println!("cargo:rustc-link-search=native={libdir}");

    for name in LLVM_LIBS {
        println!("cargo:rustc-link-lib=static={name}");
    }
    for name in SYSTEM_LIBS {
        println!("cargo:rustc-link-lib=dylib={name}");
    }
}
