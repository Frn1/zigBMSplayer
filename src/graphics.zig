const std = @import("std");

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

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
