const std = @import("std");

/// Vectorscan version (from vendor/vectorscan/CMakeLists.txt)
const VECTORSCAN_VERSION = "5.4.12";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // CPU target option (default: native)
    const cpu_target = b.option([]const u8, "mcpu", "Target CPU for optimization (default: native)") orelse "native";

    // Force rebuild option
    const force_rebuild = b.option(bool, "force-vectorscan", "Force CMake rebuild even if libs exist") orelse false;

    // Install vectorscan libraries
    const vectorscan_step = installVectorscanWithChimera(b, optimize, force_rebuild, cpu_target);

    // Create modules for package consumers
    _ = b.addModule("vectorscan", .{
        .root_source_file = b.path("src/vectorscan.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = b.addModule("chimera", .{
        .root_source_file = b.path("src/chimera.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Test step
    const vectorscan_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/vectorscan.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    addVectorscanWithChimera(vectorscan_tests, b);
    vectorscan_tests.step.dependOn(vectorscan_step);

    const chimera_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/chimera.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    addVectorscanWithChimera(chimera_tests, b);
    chimera_tests.step.dependOn(vectorscan_step);

    const run_vectorscan_tests = b.addRunArtifact(vectorscan_tests);
    const run_chimera_tests = b.addRunArtifact(chimera_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_vectorscan_tests.step);
    test_step.dependOn(&run_chimera_tests.step);
}

/// Install vectorscan + chimera from source using CMake
pub fn installVectorscanWithChimera(b: *std.Build, optimize: std.builtin.OptimizeMode, force_rebuild: bool, cpu: []const u8) *std.Build.Step {
    // Check if libraries already exist in install directory (unless force rebuild)
    if (!force_rebuild) {
        const lib_dir = b.getInstallPath(.lib, "");
        const libhs_path = b.pathJoin(&.{ lib_dir, b.fmt("libhs-{s}.a", .{VECTORSCAN_VERSION}) });
        const libchimera_path = b.pathJoin(&.{ lib_dir, b.fmt("libchimera-{s}.a", .{VECTORSCAN_VERSION}) });
        const libpcre_path = b.pathJoin(&.{ lib_dir, b.fmt("libpcre-{s}.a", .{VECTORSCAN_VERSION}) });

        const libs_exist = blk: {
            std.fs.accessAbsolute(libhs_path, .{}) catch break :blk false;
            std.fs.accessAbsolute(libchimera_path, .{}) catch break :blk false;
            std.fs.accessAbsolute(libpcre_path, .{}) catch break :blk false;
            break :blk true;
        };

        if (libs_exist) {
            const noop_step = b.step("vectorscan-cached", "Vectorscan libraries exist (cached)");
            return noop_step;
        }
    }

    const build_dir = b.cache_root.join(b.allocator, &.{"vectorscan-build"}) catch @panic("OOM");
    const zig_exe = b.graph.zig_exe;

    // CMake configure step
    const cmake_configure = b.addSystemCommand(&.{
        "cmake",
        "-S",
        "vendor/vectorscan",
        "-B",
        build_dir,
        "-DCMAKE_BUILD_TYPE=Release",
        b.fmt("-DCMAKE_C_COMPILER={s}", .{zig_exe}),
        b.fmt("-DCMAKE_CXX_COMPILER={s}", .{zig_exe}),
        "-DCMAKE_C_COMPILER_ARG1=cc",
        "-DCMAKE_CXX_COMPILER_ARG1=c++",
        "-DCMAKE_C_FLAGS=-ffunction-sections -fdata-sections -fno-sanitize=all",
        "-DCMAKE_CXX_FLAGS=-ffunction-sections -fdata-sections -fno-sanitize=all",
        "-DUSE_CPU_NATIVE=OFF",
        b.fmt("-DARCH_C_FLAGS=-mcpu={s}", .{cpu}),
        b.fmt("-DARCH_CXX_FLAGS=-mcpu={s}", .{cpu}),
        "-DBUILD_STATIC_LIBS=ON",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DBUILD_CHIMERA=ON",
        "-DBUILD_EXAMPLES=OFF",
        "-DBUILD_BENCHMARKS=OFF",
        "-DBUILD_TOOLS=OFF",
        "-DBUILD_UNIT=OFF",
        "-DBUILD_DOC=OFF",
        "-DPCRE_BUILD_TESTS=OFF",
        "-DPCRE_SUPPORT_LIBREADLINE=OFF",
        "-DPCRE_SUPPORT_LIBBZ2=OFF",
        "-Wno-dev",
    });

    // CMake build step
    const cmake_build = b.addSystemCommand(&.{
        "cmake",
        "--build",
        build_dir,
        "--config",
        "Release",
        "--parallel",
        "8",
    });
    cmake_build.step.dependOn(&cmake_configure.step);

    // Library paths
    const libhs_src = b.cache_root.join(b.allocator, &.{ "vectorscan-build", "lib", "libhs.a" }) catch @panic("OOM");
    const libchimera_src = b.cache_root.join(b.allocator, &.{ "vectorscan-build", "lib", "libchimera.a" }) catch @panic("OOM");
    const libpcre_src = b.cache_root.join(b.allocator, &.{ "vectorscan-build", "lib", "libpcre.a" }) catch @panic("OOM");

    const should_strip = optimize != .Debug;

    const libhs_dest = b.fmt("lib/libhs-{s}.a", .{VECTORSCAN_VERSION});
    const libchimera_dest = b.fmt("lib/libchimera-{s}.a", .{VECTORSCAN_VERSION});
    const libpcre_dest = b.fmt("lib/libpcre-{s}.a", .{VECTORSCAN_VERSION});

    // Install libraries (with optional stripping)
    const install_libhs: *std.Build.Step.InstallFile = blk: {
        if (should_strip) {
            const strip_libhs = b.addSystemCommand(&.{ "strip", "-S", libhs_src });
            strip_libhs.step.dependOn(&cmake_build.step);
            const install = b.addInstallFile(.{ .cwd_relative = libhs_src }, libhs_dest);
            install.step.dependOn(&strip_libhs.step);
            break :blk install;
        } else {
            const install = b.addInstallFile(.{ .cwd_relative = libhs_src }, libhs_dest);
            install.step.dependOn(&cmake_build.step);
            break :blk install;
        }
    };

    const install_libchimera: *std.Build.Step.InstallFile = blk: {
        if (should_strip) {
            const strip = b.addSystemCommand(&.{ "strip", "-S", libchimera_src });
            strip.step.dependOn(&cmake_build.step);
            const install = b.addInstallFile(.{ .cwd_relative = libchimera_src }, libchimera_dest);
            install.step.dependOn(&strip.step);
            break :blk install;
        } else {
            const install = b.addInstallFile(.{ .cwd_relative = libchimera_src }, libchimera_dest);
            install.step.dependOn(&cmake_build.step);
            break :blk install;
        }
    };

    const install_libpcre: *std.Build.Step.InstallFile = blk: {
        if (should_strip) {
            const strip = b.addSystemCommand(&.{ "strip", "-S", libpcre_src });
            strip.step.dependOn(&cmake_build.step);
            const install = b.addInstallFile(.{ .cwd_relative = libpcre_src }, libpcre_dest);
            install.step.dependOn(&strip.step);
            break :blk install;
        } else {
            const install = b.addInstallFile(.{ .cwd_relative = libpcre_src }, libpcre_dest);
            install.step.dependOn(&cmake_build.step);
            break :blk install;
        }
    };

    // Install headers
    const install_hs_h = b.addInstallFile(b.path("vendor/vectorscan/src/hs.h"), "include/hs/hs.h");
    const install_hs_common_h = b.addInstallFile(b.path("vendor/vectorscan/src/hs_common.h"), "include/hs/hs_common.h");
    const install_hs_compile_h = b.addInstallFile(b.path("vendor/vectorscan/src/hs_compile.h"), "include/hs/hs_compile.h");
    const install_hs_runtime_h = b.addInstallFile(b.path("vendor/vectorscan/src/hs_runtime.h"), "include/hs/hs_runtime.h");
    // Generated header from CMake build
    const hs_version_h_src = b.cache_root.join(b.allocator, &.{ "vectorscan-build", "hs_version.h" }) catch @panic("OOM");
    const install_hs_version_h = b.addInstallFile(.{ .cwd_relative = hs_version_h_src }, "include/hs/hs_version.h");
    install_hs_version_h.step.dependOn(&cmake_build.step);
    const install_ch_h = b.addInstallFile(b.path("vendor/vectorscan/chimera/ch.h"), "include/ch/ch.h");
    const install_ch_common_h = b.addInstallFile(b.path("vendor/vectorscan/chimera/ch_common.h"), "include/ch/ch_common.h");
    const install_ch_compile_h = b.addInstallFile(b.path("vendor/vectorscan/chimera/ch_compile.h"), "include/ch/ch_compile.h");
    const install_ch_runtime_h = b.addInstallFile(b.path("vendor/vectorscan/chimera/ch_runtime.h"), "include/ch/ch_runtime.h");

    // Add to default install step
    b.getInstallStep().dependOn(&install_libhs.step);
    b.getInstallStep().dependOn(&install_libchimera.step);
    b.getInstallStep().dependOn(&install_libpcre.step);
    b.getInstallStep().dependOn(&install_hs_h.step);
    b.getInstallStep().dependOn(&install_hs_common_h.step);
    b.getInstallStep().dependOn(&install_hs_compile_h.step);
    b.getInstallStep().dependOn(&install_hs_runtime_h.step);
    b.getInstallStep().dependOn(&install_hs_version_h.step);
    b.getInstallStep().dependOn(&install_ch_h.step);
    b.getInstallStep().dependOn(&install_ch_common_h.step);
    b.getInstallStep().dependOn(&install_ch_compile_h.step);
    b.getInstallStep().dependOn(&install_ch_runtime_h.step);

    // Aggregated step for dependency tracking
    const vectorscan_ready = b.step("vectorscan-ready", "Vectorscan libraries and headers installed");
    vectorscan_ready.dependOn(&install_libhs.step);
    vectorscan_ready.dependOn(&install_libchimera.step);
    vectorscan_ready.dependOn(&install_libpcre.step);
    vectorscan_ready.dependOn(&install_hs_h.step);
    vectorscan_ready.dependOn(&install_hs_common_h.step);
    vectorscan_ready.dependOn(&install_hs_compile_h.step);
    vectorscan_ready.dependOn(&install_hs_runtime_h.step);
    vectorscan_ready.dependOn(&install_hs_version_h.step);
    vectorscan_ready.dependOn(&install_ch_h.step);
    vectorscan_ready.dependOn(&install_ch_common_h.step);
    vectorscan_ready.dependOn(&install_ch_compile_h.step);
    vectorscan_ready.dependOn(&install_ch_runtime_h.step);
    return vectorscan_ready;
}

/// Add vectorscan + chimera to a compilation step
pub fn addVectorscanWithChimera(step: *std.Build.Step.Compile, b: *std.Build) void {
    const include_path = b.getInstallPath(.header, "");
    step.addIncludePath(.{ .cwd_relative = include_path });
    step.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ include_path, "hs" }) });
    step.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ include_path, "ch" }) });

    const lib_dir = b.getInstallPath(.lib, "");
    const libhs_path = b.pathJoin(&.{ lib_dir, b.fmt("libhs-{s}.a", .{VECTORSCAN_VERSION}) });
    const libchimera_path = b.pathJoin(&.{ lib_dir, b.fmt("libchimera-{s}.a", .{VECTORSCAN_VERSION}) });
    const libpcre_path = b.pathJoin(&.{ lib_dir, b.fmt("libpcre-{s}.a", .{VECTORSCAN_VERSION}) });
    step.addObjectFile(.{ .cwd_relative = libhs_path });
    step.addObjectFile(.{ .cwd_relative = libchimera_path });
    step.addObjectFile(.{ .cwd_relative = libpcre_path });

    step.linkLibCpp();
}
