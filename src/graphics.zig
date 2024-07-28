const std = @import("std");

const c = @import("consts.zig");
const utils = @import("utils.zig");

const ChartType = @import("rhythm/conductor.zig").ChartType;
const Object = @import("rhythm/object.zig").Object;
const Lane = @import("rhythm/objects/note.zig").Lane;

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

pub const ScrollDirection = enum { Up, Down };

pub fn drawText(text: [:0]const u8, renderer: *sdl.SDL_Renderer, x: c_int, y: c_int, font: *sdl.TTF_Font) !void {
    const surface_text: *sdl.SDL_Surface = sdl.TTF_RenderText_Solid(font, text, .{ .r = 255, .g = 255, .b = 255 }).?;
    defer sdl.SDL_FreeSurface(surface_text);
    const texture_text: *sdl.SDL_Texture = sdl.SDL_CreateTextureFromSurface(renderer, surface_text).?;
    defer sdl.SDL_DestroyTexture(texture_text);

    var message_rect: sdl.SDL_Rect = sdl.SDL_Rect{
        .x = x,
        .y = y,
    };
    try utils.sdlAssert(sdl.SDL_QueryTexture(texture_text, null, null, &message_rect.w, &message_rect.h) == 0);
    try utils.sdlAssert(sdl.SDL_RenderCopy(renderer, texture_text, null, &message_rect) == 0);
}

pub fn getKeyTypeForLane(lane: Lane) enum { scratch, white, black } {
    return switch (lane) {
        .Scratch_P1,
        .Scratch_P2,
        => .scratch,
        .White1_P1,
        .White2_P1,
        .White3_P1,
        .White4_P1,
        .White1_P2,
        .White2_P2,
        .White3_P2,
        .White4_P2,
        => .white,
        .Black1_P1,
        .Black2_P1,
        .Black3_P1,
        .Black1_P2,
        .Black2_P2,
        .Black3_P2,
        => .black,
    };
}

pub inline fn getColorForLane(lane: Lane) sdl.SDL_Color {
    return switch (getKeyTypeForLane(lane)) {
        .scratch => sdl.SDL_Color{ .r = 255, .g = 0, .b = 0, .a = 0 },
        .white => sdl.SDL_Color{ .r = 255, .g = 240, .b = 200, .a = 0 },
        .black => sdl.SDL_Color{ .r = 0, .g = 0, .b = 255, .a = 0 },
    };
}

pub inline fn getWidthForLane(lane: Lane) c_int {
    return switch (getKeyTypeForLane(lane)) {
        .scratch => c.note_width_scratch,
        .white => c.note_width_white,
        .black => c.note_width_black,
    };
}

pub inline fn getYFromPosition(
    object_position: Object.Position,
    current_position: Object.Position,
    scroll_speed: Object.Position,
    scroll_direction: ScrollDirection,
    height: c_int,
) c_int {
    var output = @as(c_int, @intFromFloat(@round((current_position - object_position) * scroll_speed * c.beat_height)));

    switch (scroll_direction) {
        .Up => output += c.upscroll_judgement_line_y,
        .Down => output = -output + c.downscroll_judgement_line_y - height,
    }

    return output;
}

// Each element should only be present once
const lane_positions_5k = [_]Lane{
    // P1
    .Scratch_P1, .White1_P1, .Black1_P1, .White2_P1, .Black2_P1, .White3_P1,
};
const lane_positions_7k = [_]Lane{
    // P1
    .Scratch_P1, .White1_P1, .Black1_P1, .White2_P1, .Black2_P1, .White3_P1, .Black3_P1, .White4_P1,
};
const lane_positions_10k = [_]Lane{
    // P1
    .Scratch_P1, .White1_P1, .Black1_P1, .White2_P1, .Black2_P1, .White3_P1,
    // P2
    .White1_P2,  .Black1_P2, .White2_P2, .Black2_P2, .White3_P2, .Scratch_P2,
};
const lane_positions_14k = [_]Lane{
    // P1
    .Scratch_P1, .White1_P1, .Black1_P1, .White2_P1, .Black2_P1, .White3_P1, .Black3_P1, .White4_P1,
    // P2
    .White1_P2,  .Black1_P2, .White2_P2, .Black2_P2, .White3_P2, .Black3_P2, .White4_P2, .Scratch_P2,
};

pub inline fn getXForLane(
    lane: Lane,
    chart_type: ChartType,
) c_int {
    var output: c_int = 0;
    const lane_positions = switch (chart_type) {
        .beat5k => &lane_positions_5k,
        .beat7k => &lane_positions_7k,
        .beat10k => &lane_positions_10k,
        .beat14k => &lane_positions_14k,
    };
    const position = std.mem.indexOf(Lane, lane_positions, &.{lane}).?;
    for (0..position) |i| {
        output += getWidthForLane(lane_positions[i]);
    }
    return output;
}

/// Returns `true` if a y position is off screen
pub inline fn isOffScreen(y: c_int) bool {
    return y < 0 or y > c.screen_height;
}

pub inline fn getBarlineWidth(chart_type: ChartType) c_int {
    var output: c_int = 0;
    const lane_positions = switch (chart_type) {
        .beat5k => &lane_positions_5k,
        .beat7k => &lane_positions_7k,
        .beat10k => &lane_positions_10k,
        .beat14k => &lane_positions_14k,
    };
    for (lane_positions) |lane| {
        output += getWidthForLane(lane);
    }
    return output;
}
