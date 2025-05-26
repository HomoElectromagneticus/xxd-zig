const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to
    // select between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here,
    // we do not set a preferred mode, allowing the user to decide.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "xxd-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_exe = b.addRunArtifact(exe);

    // This creates a build step. It will be visible in the `zig build --help`
    // menu, and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default of "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_exe.step);

    // Adding clap for command-line argument parsing
    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));
}
