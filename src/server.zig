const std = @import("std");
const argparse = @import("MasterQ32/zig-args");
const network = @import("MasterQ32/zig-network");
const shared = @import("shared.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    const allocator: std.mem.Allocator = gpa.allocator();

    const Args = struct {
        port: u16,
    };
    const args: Args = args: {
        const result = try argparse.parseForCurrentProcess(struct {
            port: ?u16 = null,
        }, allocator, .silent);
        defer result.deinit();

        break :args Args{
            .port = result.options.port orelse return error.MissingPortNumber,
        };
    };

    var host_socket = try network.Socket.create(.ipv4, .tcp);
    defer host_socket.close();

    try host_socket.bindToPort(args.port);
    try host_socket.listen();

    var terminate_server = std.atomic.Atomic(bool).init(false);

    const server_cmds_handler_thread = try std.Thread.spawn(.{}, serverCmdsHandling, .{&terminate_server});
    defer server_cmds_handler_thread.join();

    while (!terminate_server.load(.Acquire)) {
        var p1_sock = try host_socket.accept();
        defer p1_sock.close();

        var p2_sock = try host_socket.accept();
        defer p2_sock.close();

        playGame(p1_sock, p2_sock) catch |err| return switch (err) {
            error.EndOfStream => continue,
            else => err,
        };
    }
}

fn playGame(p1_sock: network.Socket, p2_sock: network.Socket) !void {
    const p1_out = p1_sock.writer();
    const p1_in = p1_sock.reader();

    const p2_out = p2_sock.writer();
    const p2_in = p2_sock.reader();

    var p1_points: u2 = 0;
    var p2_points: u2 = 0;

    while (!shared.gameMustEnd(p1_points, p2_points)) {
        const p1_hand_shape = try p1_in.readEnum(shared.HandShape, shared.endian);
        const p2_hand_shape = try p2_in.readEnum(shared.HandShape, shared.endian);

        const p1_2_order = p1_hand_shape.partialOrder(p2_hand_shape);

        p1_points += @boolToInt(p1_2_order == .gt);
        p2_points += @boolToInt(p1_2_order == .lt);

        try p1_out.writeInt(shared.HandShape.Tag, @enumToInt(p1_hand_shape), shared.endian);
        try p2_out.writeInt(shared.HandShape.Tag, @enumToInt(p2_hand_shape), shared.endian);

        try p1_out.writeInt(shared.HandShape.Tag, @enumToInt(p2_hand_shape), shared.endian);
        try p2_out.writeInt(shared.HandShape.Tag, @enumToInt(p1_hand_shape), shared.endian);

        try p1_out.writeInt(u8, p1_points, shared.endian);
        try p1_out.writeInt(u8, p2_points, shared.endian);

        try p2_out.writeInt(u8, p2_points, shared.endian);
        try p2_out.writeInt(u8, p1_points, shared.endian);
    }
}

fn serverCmdsHandling(
    p_terminate_server: *std.atomic.Atomic(bool),
) void {
    defer p_terminate_server.store(true, .Release);

    var buffer: [128]u8 = undefined;
    while (true) {
        const user_input = std.io.getStdIn().reader().readUntilDelimiter(&buffer, '\n') catch |err| {
            while (!std.debug.getStderrMutex().tryLock()) {}
            defer std.debug.getStderrMutex().unlock();
            switch (err) {
                error.StreamTooLong => {},
                else => std.io.getStdErr().writer().print("\nFailed to process command. Error: {s}.\n", .{@errorName(err)}) catch {},
            }
            continue;
        };

        if (user_input.len == 0) {} else if (std.mem.eql(u8, user_input, "TERMINATE")) {
            break;
        } else {
            while (!std.debug.getStderrMutex().tryLock()) {}
            defer std.debug.getStderrMutex().unlock();

            std.io.getStdErr().writer().print("\nUnrecognized command '{s}'.\n", .{user_input}) catch {};
        }
    }
}
