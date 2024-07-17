const std = @import("std");

fn addSDLLibrary(name: []const u8, b: *std.Build, target: std.Build.ResolvedTarget, exe: *std.Build.Step.Compile) !void {
    var arena = std.heap.ArenaAllocator.init(b.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sdl_triple = try std.fmt.allocPrint(allocator, "{s}-w64-mingw32", .{
        if (target.result.ptrBitWidth() == 64) "x86_64" else "i686",
    });
    const include_path = try std.fs.path.join(allocator, &.{ sdl_triple, "include" });
    const include_name_path = try std.fs.path.join(allocator, &.{ sdl_triple, "include", name });
    const bin_path = try std.fs.path.join(allocator, &.{ sdl_triple, "bin" });
    const lib_path = try std.fs.path.join(allocator, &.{ sdl_triple, "lib" });

    const sys_lib_name = try std.mem.join(allocator, ".", &.{ name, "dll" });
    const sys_lib_path = try std.fs.path.join(allocator, &.{ bin_path, sys_lib_name });

    const dependency = b.dependency(name, .{});
    exe.addIncludePath(dependency.path(include_path));
    exe.addIncludePath(dependency.path(include_name_path));
    exe.addLibraryPath(dependency.path(bin_path));
    exe.addLibraryPath(dependency.path(lib_path));

    const install = b.getInstallStep();
    const install_data = b.addInstallBinFile(
        .{
            .dependency = .{
                .dependency = dependency,
                .sub_path = sys_lib_path,
            },
        },
        sys_lib_name,
    );
    install.dependOn(&install_data.step);

    exe.linkSystemLibrary(name);
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "rhythmicZig",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .linkage = .dynamic,
    });

    try addSDLLibrary("SDL2", b, target, exe);
    try addSDLLibrary("SDL2_ttf", b, target, exe);

    const miniaudio_dependency = b.dependency("miniaudio", .{});
    
    exe.addCSourceFile(.{
        .file = miniaudio_dependency.path("extras/stb_vorbis.c"),
        .flags = &.{},
    });
    exe.addCSourceFile(.{
        .file = miniaudio_dependency.path("extras/miniaudio_split/miniaudio.c"),
        .flags = &.{
            "-fno-sanitize=undefined",
        },
    });
    exe.addSystemIncludePath(miniaudio_dependency.path("extras"));
    exe.addSystemIncludePath(miniaudio_dependency.path("extras/miniaudio_split"));

    const install = b.getInstallStep();
    const install_data = b.addInstallDirectory(
        .{
            .install_dir = .{
                .prefix = {},
            },
            .install_subdir = "fonts",
            .source_dir = .{
                .cwd_relative = "fonts",
            },
        },
    );
    install.dependOn(&install_data.step);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.setCwd(.{ .cwd_relative = "zig-out" });

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
