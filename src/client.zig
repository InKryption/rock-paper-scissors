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
        hostname: [:0]const u8,
    };
    const args: Args = args: {
        const result = try argparse.parseForCurrentProcess(struct {
            port: ?u16 = null,
            hostname: ?[:0]const u8 = null,
        }, allocator, .silent);
        defer result.deinit();

        const hostname = try allocator.dupeZ(u8, result.options.hostname orelse return error.MissingHostName);
        errdefer allocator.free(hostname);

        break :args Args{
            .port = result.options.port orelse return error.MissingPortNumber,
            .hostname = hostname,
        };
    };
    defer allocator.free(args.hostname);

    var server_socket = try network.connectToHost(allocator, args.hostname, args.port, .tcp);
    defer server_socket.close();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    const srvout = server_socket.writer();
    const srvin = server_socket.reader();

    var user_points: u2 = 0;
    var opponent_points: u2 = 0;

    while (true) {
        const user_hand_shape: shared.HandShape = while (true) {
            var buff: [32]u8 = undefined;
            const user_input = try stdin.readUntilDelimiter(&buff, '\n');

            const hand_shape_values = comptime std.enums.values(shared.HandShape);
            break for (hand_shape_values) |hs| {
                const tag_name = @tagName(hs);
                if (std.mem.eql(u8, tag_name, user_input)) break hs;
            } else {
                try stdout.print("'{s}' is not a shape. Input one of: ", .{user_input});
                for (hand_shape_values[0 .. hand_shape_values.len - 1]) |hs| {
                    try stdout.print("{s}, ", .{@tagName(hs)});
                } else try stdout.print("or {s}.\n", .{@tagName(hand_shape_values[hand_shape_values.len - 1])});
                continue;
            };
        } else unreachable;

        try srvout.writeInt(shared.HandShape.Tag, @enumToInt(user_hand_shape), shared.endian);

        if (if (srvin.readEnum(shared.HandShape, shared.endian)) |returned_hs| (user_hand_shape != returned_hs) else |_| true) {
            return error.ServerFailedToConfirmHandShape;
        }

        const opponent_hand_shape: shared.HandShape = try srvin.readEnum(shared.HandShape, shared.endian);
        try stdout.print("Opponent played {s} against your {s}.\n", .{ @tagName(opponent_hand_shape), @tagName(user_hand_shape) });

        const user_opponent_hand_shape_order = user_hand_shape.partialOrder(opponent_hand_shape);
        user_points += @boolToInt(user_opponent_hand_shape_order == .gt);
        opponent_points += @boolToInt(user_opponent_hand_shape_order == .lt);

        if (if (srvin.readInt(u8, shared.endian)) |returned_user_points| (returned_user_points != user_points) else |_| true) {
            return error.ServerFailedToConfirmUserPoints;
        }
        if (if (srvin.readInt(u8, shared.endian)) |returned_opponent_points| (returned_opponent_points != opponent_points) else |_| true) {
            return error.ServerFailedToConfirmUserPoints;
        }

        switch (user_opponent_hand_shape_order) {
            .eq => try stdout.writeAll("Draw. No score.\n"),
            .lt => try stdout.writeAll("Opponent scored.\n"),
            .gt => try stdout.writeAll("You scored.\n"),
        }

        try stdout.print("Score: {} <> {}\n", .{ user_points, opponent_points });
        if (shared.gameMustEnd(user_points, opponent_points)) break;
    }

    switch (std.math.order(user_points, opponent_points)) {
        .eq => unreachable,
        .gt => try stdout.writeAll("You win.\n"),
        .lt => try stdout.writeAll("You lose.\n"),
    }
}
