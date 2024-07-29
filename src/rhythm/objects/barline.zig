const std = @import("std");

const gfx = @import("../../graphics.zig");
const c = @import("../../consts.zig");

const sdlAssert = @import("../../utils.zig").sdlAssert;

const State = @import("../conductor.zig").Conductor.State;
const ChartType = @import("../conductor.zig").ChartType;
const Object = @import("../object.zig").Object;

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

fn render(
    _: Object,
    object_position: Object.Position,
    current_position: Object.Position,
    chart_type: ChartType,
    scroll_speed: Object.Position,
    scroll_direction: gfx.ScrollDirection,
    renderer: *sdl.SDL_Renderer,
) !void {
    // change color to white
    try sdlAssert(sdl.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF) == 0);

    const y = gfx.getYFromPosition(
        object_position,
        current_position,
        scroll_speed,
        scroll_direction,
        1,
    );

    if (gfx.isOffScreen(y)) {
        return;
    }

    try sdlAssert(
        sdl.SDL_RenderDrawLine(
            renderer,
            0,
            y,
            gfx.getBarlineWidth(chart_type),
            y,
        ) == 0,
    );
}

/// Creates a Barline object.
pub fn create(_: std.mem.Allocator, beat: Object.Time) !Object {
    const object = Object{
        .beat = beat,
        .priority = -127,
        .render = render,
    };
    return object;
}
