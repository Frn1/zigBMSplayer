const std = @import("std");

const gfx = @import("../../graphics.zig");
const c = @import("../../consts.zig");

const sdlAssert = @import("../../utils.zig").sdlAssert;

const State = @import("../conductor.zig").Conductor.State;
const Object = @import("../object.zig").Object;

const BeatsPerMinute = Object.Time;

const Parameters = BeatsPerMinute;

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

fn init(object: *Object, allocator: std.mem.Allocator) !void {
    object.parameters = @ptrCast(try allocator.create(Parameters));
}

fn destroy(object: Object, allocator: std.mem.Allocator) void {
    allocator.destroy(@as(*Parameters, @alignCast(@ptrCast(object.parameters))));
}

fn process(object: Object, state: *State) void {
    if (state.seconds_per_beat < 0 or !std.math.isNormal(state.seconds_per_beat)) {
        state.*.seconds_offset = 0;
    } else {
        state.*.seconds_offset = state.convertBeatToSeconds(object.beat);
    }
    state.*.beats_offset = object.beat;
    state.*.seconds_per_beat = 60 / @as(*Parameters, @alignCast(@ptrCast(object.parameters))).*;
}

fn render(
    object: Object,
    object_position: Object.Position,
    current_position: Object.Position,
    scroll_speed: Object.Position,
    scroll_direction: gfx.ScrollDirection,
    renderer: *sdl.SDL_Renderer,
) !void {
    _ = object;

    try sdlAssert(sdl.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF) == 0);

    var rect: sdl.SDL_Rect = sdl.SDL_Rect{
        .x = c.note_width_scratch,
        .y = gfx.getYFromPosition(
            object_position,
            current_position,
            scroll_speed,
        ),
        .w = c.note_width_scratch,
        .h = c.note_height,
    };
    switch (scroll_direction) {
        .Up => rect.y = rect.y + c.upscroll_judgement_line_y,
        .Down => rect.y = -rect.y + c.downscroll_judgement_line_y - c.note_height,
    }
    try sdlAssert(sdl.SDL_RenderFillRect(renderer, &rect) == 0);
}

/// Creates a BPM object.
///
/// **Caller is responsible of calling `destroy` to destroy the object.
/// (If it's not null)**
///
/// **Note: This is NOT the same as calling `allocator.destroy`.**
pub fn createBpmObject(allocator: std.mem.Allocator, beat: Object.Time, bpm: Object.Time) !Object {
    var object = Object{
        .beat = beat,
        .init = init,
        .destroy = destroy,
        .process = process,
        .render = render,
    };
    try object.init.?(&object, allocator);
    @as(*Parameters, @alignCast(@ptrCast(object.parameters))).* = bpm;

    return object;
}
