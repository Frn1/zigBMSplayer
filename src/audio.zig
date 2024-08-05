const std = @import("std");

const ma = @cImport({
    @cDefine("MINIAUDIO_IMPLEMENTATION", {});
    @cInclude("miniaudio.h");
});

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const Conductor = @import("rhythm/conductor.zig");
const utils = @import("utils.zig");

pub fn audioThread(conductor: Conductor, start_tick: u64, audio_stop_flag: *bool) void {
    defer for (conductor.keysounds) |keysound| {
        if (keysound != null) {
            _ = ma.ma_sound_stop(keysound);
        }
    };

    // how many ticks are in a second
    const performance_frequency: f80 = @floatFromInt(sdl.SDL_GetPerformanceFrequency());

    var last_frame_end = sdl.SDL_GetPerformanceCounter();

    var state = Conductor.State{};

    while (audio_stop_flag.* == false) {
        if (sdl.SDL_GetPerformanceCounter() - last_frame_end < sdl.SDL_GetPerformanceFrequency() / 10000) {
            continue;
        }

        defer last_frame_end = sdl.SDL_GetPerformanceCounter();

        const current_performance_ticks = sdl.SDL_GetPerformanceCounter() - start_tick;
        const current_seconds: f80 = @as(f80, @floatFromInt(current_performance_ticks)) / performance_frequency;

        state.update(conductor, current_seconds, true);
    }
}
