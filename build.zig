const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Fetch dependencies from build.zig.zon
    // const lua_dep = b.dependency("zlua", .{
    //     .target = target,
    //     .optimize = optimize,
    //     .lang = .lua54,
    // });

    const sdl_bin_dep = b.dependency("sdl", .{});

    // Create the executable step
    const exe = b.addExecutable(.{
        .name = "zig_sdl3_app",
        .root_module = b.createModule(.{
            // .root_source_file = b.path("src/sample00.zig"),
            // .root_source_file = b.path("src/scriptlua.zig"),
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true, // Correct Zig 0.16.0 way to link libc
        }),
    });

    // Set up SDL3 search paths on the executable's root module
    exe.root_module.addIncludePath(sdl_bin_dep.path("x86_64-w64-mingw32/include"));
    exe.root_module.addLibraryPath(sdl_bin_dep.path("x86_64-w64-mingw32/lib"));
    exe.root_module.addLibraryPath(sdl_bin_dep.path("x86_64-w64-mingw32/bin"));

    // Link library dependencies
    exe.root_module.linkSystemLibrary("SDL3", .{});
    // exe.root_module.addImport("zlua", lua_dep.module("zlua"));

    // Register standard installation step
    b.installArtifact(exe);

    // Install runtime dependencies to the output binary directory
    // const copy_script = b.addInstallFileWithDir(
    //     b.path("script.lua"),
    //     .bin,
    //     "script.lua",
    // );
    // b.getInstallStep().dependOn(&copy_script.step);

    const target_info = target.result;
    if (target_info.os.tag == .windows) {
        const install_dll = b.addInstallFileWithDir(
            sdl_bin_dep.path("x86_64-w64-mingw32/bin/SDL3.dll"),
            .bin,
            "SDL3.dll",
        );
        b.getInstallStep().dependOn(&install_dll.step);
    }

    // Set up the run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    // Pass CLI arguments directly if provided
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    run_step.dependOn(&run_cmd.step);
}
