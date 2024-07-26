const std = @import("std");

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const c = @import("consts.zig");
const utils = @import("utils.zig");

pub fn drawText(text: [:0]u8, renderer: *sdl.SDL_Renderer, x: c_int, y: c_int, font: *sdl.TTF_Font) !void {
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

pub fn getKeyTypeForLane(lane: u7) enum { scratch, white, black } {
    if (lane == 0 or lane == 15) {
        return .scratch;
    } else if (lane < 8) {
        if (lane % 2 == 0) {
            return .black;
        } else {
            return .white;
        }
    } else {
        if (lane % 2 == 0) {
            return .white;
        } else {
            return .black;
        }
    }
}

pub fn getColorForLane(lane: u7) sdl.SDL_Color {
    return switch (getKeyTypeForLane(lane)) {
        .scratch => sdl.SDL_Color{ .r = 255, .g = 0, .b = 0, .a = 0 },
        .white => sdl.SDL_Color{ .r = 255, .g = 240, .b = 200, .a = 0 },
        .black => sdl.SDL_Color{ .r = 0, .g = 0, .b = 255, .a = 0 },
    };
}

pub fn getWidthForLane(lane: u7) c_int {
    return switch (getKeyTypeForLane(lane)) {
        .scratch => c.note_width_scratch,
        .white => c.note_width_white,
        .black => c.note_width_black,
    };
}

pub fn getXForLane(lane: u7) c_int {
    var output: c_int = 0;
    for (0..@min(lane, 8)) |i| {
        output += getWidthForLane(@intCast(i));
    }
    if (lane > 8) {
        for (8..lane) |i| {
            output += getWidthForLane(@intCast(i));
        }
    }
    return output;
}
