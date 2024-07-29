const std = @import("std");

const gfx = @import("../../graphics.zig");
const c = @import("../../consts.zig");

const sdlAssert = @import("../../utils.zig").sdlAssert;

const State = @import("../conductor.zig").Conductor.State;
const Object = @import("../object.zig").Object;

const Scroll = Object.Position;

const Parameters = Scroll;

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

fn destroy(object: Object, allocator: std.mem.Allocator) void {
    allocator.destroy(@as(*Parameters, @alignCast(@ptrCast(object.parameters))));
}

fn process(object: Object, state: *State) void {
    const new_scroll = @as(*Parameters, @alignCast(@ptrCast(object.parameters))).*;
    state.visual_pos_offset = state.calculateVisualPosition(object.beat);
    state.visual_beats_offset = @floatCast(object.beat);
    state.scroll_mul = new_scroll;
}

/// Creates a Scroll object.
///
/// **Caller is responsible of calling `destroy` to destroy the object.**
///
/// **Note: This is NOT the same as calling `allocator.destroy`.**
pub fn create(allocator: std.mem.Allocator, beat: Object.Time, scroll: Scroll) !Object {
    var object = Object{
        .beat = beat,
        .destroy = destroy,
        .process = process,
    };
    object.parameters = @ptrCast(try allocator.create(Parameters));
    @as(*Parameters, @alignCast(@ptrCast(object.parameters))).* = scroll;

    return object;
}
