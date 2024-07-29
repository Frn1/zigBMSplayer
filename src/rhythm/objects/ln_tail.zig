const std = @import("std");

const Object = @import("../object.zig").Object;

/// Creates a Long note tail object.
pub fn create(_: std.mem.Allocator, beat: Object.Time) !Object {
    return Object{
        .beat = beat,
    };
}
