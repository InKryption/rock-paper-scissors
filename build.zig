const std = @import("std");

const @"MasterQ32/zig-args": std.build.Pkg = .{
    .name = "MasterQ32/zig-args",
    .path = .{ .path = "dep/MasterQ32/zig-args/args.zig" },
};

const @"MasterQ32/zig-network": std.build.Pkg = .{
    .name = "MasterQ32/zig-network",
    .path = .{ .path = "dep/MasterQ32/zig-network/network.zig" },
};

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const server_exe = b.addExecutable("server-exe", "src/server.zig");
    server_exe.setTarget(target);
    server_exe.setBuildMode(mode);
    server_exe.install();
    server_exe.addPackage(@"MasterQ32/zig-args");
    server_exe.addPackage(@"MasterQ32/zig-network");

    const client_exe = b.addExecutable("client-exe", "src/client.zig");
    client_exe.setTarget(target);
    client_exe.setBuildMode(mode);
    client_exe.install();
    client_exe.addPackage(@"MasterQ32/zig-args");
    client_exe.addPackage(@"MasterQ32/zig-network");

    const run_step = b.step("run", "Run the selected component.");

    const Component = enum { server, client };
    if (b.option(Component, "component", "Component to use.")) |component| {
        const selected_exe: *std.build.LibExeObjStep = switch (component) {
            .server => server_exe,
            .client => client_exe,
        };
        const run_cmd = selected_exe.run();
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        run_step.dependOn(&run_cmd.step);
    } else {
        const log_warning = b.addLog("Please specify `-Dcomponent` to run.\n", .{});
        run_step.dependOn(&log_warning.step);
    }
}
