const std = @import("std");

const gfx = @import("../../graphics.zig");
const c = @import("../../consts.zig");

const sdlAssert = @import("../../utils.zig").sdlAssert;

const ChartType = @import("../conductor.zig").ChartType;
const State = @import("../conductor.zig").Conductor.State;
const Object = @import("../object.zig").Object;
const Keysound = @import("bgm.zig").Keysound;
const Lane = @import("note.zig").Lane;

const ma = @cImport({
    @cDefine("MINIAUDIO_IMPLEMENTATION", {});
    @cInclude("miniaudio.h");
});

pub const Parameters = struct {
    lane: Lane,
    sound: ?Keysound = null,
    tail_obj_index: usize = undefined,
};

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

fn destroy(object: Object, allocator: std.mem.Allocator) void {
    allocator.destroy(Object.castParameters(Parameters, object.parameters));
}

fn canHit(
    object: Object,
    lane: Lane,
) bool {
    const parameters = Object.castParameters(Parameters, object.parameters);
    if (lane != parameters.lane) {
        return false;
    }
    return true;
}

fn hit(
    object: Object,
) void {
    const parameters = Object.castParameters(Parameters, object.parameters);
    if (parameters.sound != null) {
        _ = ma.ma_sound_seek_to_pcm_frame(parameters.sound, 0);
        _ = ma.ma_sound_start(parameters.sound);
    }
}

fn render(
    object: Object,
    object_position: Object.Position,
    current_position: Object.Position,
    all_positions: []Object.Position,
    chart_type: ChartType,
    scroll_speed: Object.Position,
    scroll_direction: gfx.ScrollDirection,
    renderer: *sdl.SDL_Renderer,
) !void {
    const parameters = Object.castParameters(Parameters, object.parameters);

    const tail_y = gfx.getYFromPosition(
        all_positions[parameters.tail_obj_index],
        current_position,
        scroll_speed,
        scroll_direction,
        c.note_height,
    );
    // if (gfx.isOffScreen(tail_y)) {
    //     return;
    // }

    const head_y = gfx.getYFromPosition(
        object_position,
        current_position,
        scroll_speed,
        scroll_direction,
        c.note_height,
    );
    const rect: sdl.SDL_Rect = sdl.SDL_Rect{
        .x = gfx.getXForLane(parameters.lane, chart_type),
        .y = if (scroll_direction == .Down) head_y + c.note_height else head_y,
        .w = gfx.getWidthForLane(parameters.lane),
        .h = tail_y - head_y,
    };

    const color = gfx.getColorForLane(parameters.lane);
    try sdlAssert(sdl.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a) == 0);
    try sdlAssert(sdl.SDL_RenderFillRect(renderer, &rect) == 0);
}

/// Creates a Long note head object.
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
        .canHit = canHit,
    };
    object.parameters = @ptrCast(try allocator.create(Parameters));
    const params = Object.castParameters(Parameters, object.parameters);
    params.lane = lane;
    params.sound = sound;

    return object;
}
