const std = @import("std");

const gfx = @import("../../graphics.zig");
const c = @import("../../consts.zig");

const sdlAssert = @import("../../utils.zig").sdlAssert;

const ChartType = @import("../conductor.zig").ChartType;
const State = @import("../conductor.zig").Conductor.State;
const Object = @import("../object.zig").Object;
const Keysound = @import("bgm.zig").Keysound;

const ma = @cImport({
    @cDefine("MINIAUDIO_IMPLEMENTATION", {});
    @cInclude("miniaudio.h");
});

pub const Lane = enum {
    // P1 Lanes
    Scratch_P1,
    White1_P1,
    Black1_P1,
    White2_P1,
    Black2_P1,
    White3_P1,
    Black3_P1,
    White4_P1,
    // P2 Lanes
    Scratch_P2,
    White1_P2,
    Black1_P2,
    White2_P2,
    Black2_P2,
    White3_P2,
    Black3_P2,
    White4_P2,
};

const Parameters = struct {
    lane: Lane,
    sound: ?Keysound = null,
};

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

fn destroy(object: Object, allocator: std.mem.Allocator) void {
    allocator.destroy(@as(*Parameters, @alignCast(@ptrCast(object.parameters))));
}

fn hit(
    object: Object,
) void {
    const parameters = @as(*Parameters, @alignCast(@ptrCast(object.parameters)));
    if (parameters.sound != null) {
        _ = ma.ma_sound_seek_to_pcm_frame(parameters.sound, 0);
        _ = ma.ma_sound_start(parameters.sound);
    }
}

fn render(
    object: Object,
    object_position: Object.Position,
    current_position: Object.Position,
    chart_type: ChartType,
    scroll_speed: Object.Position,
    scroll_direction: gfx.ScrollDirection,
    renderer: *sdl.SDL_Renderer,
) !void {
    const parameters = @as(*Parameters, @alignCast(@ptrCast(object.parameters)));

    const color = gfx.getColorForLane(parameters.lane);

    try sdlAssert(sdl.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a) == 0);

    var rect: sdl.SDL_Rect = sdl.SDL_Rect{
        .x = gfx.getXForLane(parameters.lane, chart_type),
        .y = gfx.getYFromPosition(
            object_position,
            current_position,
            scroll_speed,
            scroll_direction,
            c.note_height,
        ),
        .w = gfx.getWidthForLane(parameters.lane),
        .h = c.note_height,
    };
    if (gfx.isOffScreen(rect.y)) {
        return;
    }
    try sdlAssert(sdl.SDL_RenderFillRect(renderer, &rect) == 0);
}

/// Creates a Note object.
///
/// **Caller is responsible of calling `destroy` to destroy the object.**
///
/// **Note: This is NOT the same as calling `allocator.destroy`.**
pub fn create(allocator: std.mem.Allocator, beat: Object.Time, lane: Lane, sound: ?Keysound) !Object {
    var object = Object{
        .beat = beat,
        .destroy = destroy,
        .render = render,
        .hit = hit,
    };
    object.parameters = @ptrCast(try allocator.create(Parameters));
    const params = @as(*Parameters, @alignCast(@ptrCast(object.parameters)));
    params.lane = lane;
    params.sound = sound;

    return object;
}
