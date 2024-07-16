const std = @import("std");

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_mixer.h");
    @cInclude("SDL2/SDL_ttf.h");
});

pub fn sdlAssert(ok: bool) error{SdlError}!void {
    if (!ok) {
        const error_text = sdl.SDL_GetError();
        std.log.err("ERROR: SDL Error! {s}", .{error_text});
        // We've already crashed so it doesn't really matter if this succeeds
        _ = sdl.SDL_ShowSimpleMessageBox(sdl.SDL_MESSAGEBOX_ERROR, "Whoops!", error_text, null);
        return error.SdlError;
    }
}
