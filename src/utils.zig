const std = @import("std");

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_mixer.h");
    @cInclude("SDL2/SDL_ttf.h");
});

pub fn sdlAssert(ok: bool) error{SdlError}!void {
    if (!ok) {
        const error_text = sdl.SDL_GetError();
        showError("SDL Error!", error_text);
        return error.SdlError;
    }
}

pub fn showError(main_text: [*c]const u8, error_text: [*c]const u8) void {
    std.log.err("ERROR: {s} ({s})", .{ main_text, error_text });
    // I dont think it really matters if this succeeds or not
    _ = sdl.SDL_ShowSimpleMessageBox(sdl.SDL_MESSAGEBOX_ERROR, main_text, error_text, null);
}
