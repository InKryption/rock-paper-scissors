const std = @import("std");
const builtin = @import("builtin");

pub const endian: std.builtin.Endian = .Little;

pub const PlayerId = enum(u1) { p1 = 0, p2 = 1 };

pub const HandShape = enum(u8) {
    pub const Tag = std.meta.Tag(HandShape);
    rock = 0,
    paper = 1,
    scissors = 2,

    pub fn partialOrder(a: HandShape, b: HandShape) std.math.Order {
        return switch (a) {
            .rock => @as(std.math.Order, switch (b) {
                .rock => .eq,
                .paper => .lt,
                .scissors => .gt,
            }),
            .paper => @as(std.math.Order, switch (b) {
                .rock => .gt,
                .paper => .eq,
                .scissors => .lt,
            }),
            .scissors => @as(std.math.Order, switch (b) {
                .rock => .lt,
                .paper => .gt,
                .scissors => .eq,
            }),
        };
    }
};

pub fn gameMustEnd(p1_points: u2, p2_points: u2) bool {
    return std.math.max(p1_points, p2_points) >= 3 and p1_points != p2_points;
}
