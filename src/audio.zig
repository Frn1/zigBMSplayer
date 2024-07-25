const std = @import("std");

const ma = @cImport({
    @cDefine("MINIAUDIO_IMPLEMENTATION", {});
    @cInclude("miniaudio.h");
});

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const rhythm = @import("rhythm.zig");
const utils = @import("utils.zig");

pub fn audioThread(conductor: *rhythm.Conductor, start_tick: u64, audio_stop_flag: *bool) void {
    // how many ticks are in a second
    const performance_frequency: f80 = @floatFromInt(sdl.SDL_GetPerformanceFrequency());

    var last_frame_end = sdl.SDL_GetPerformanceCounter();

    var state = rhythm.ConductorState{};

    while (audio_stop_flag.* == false) {
        if (sdl.SDL_GetPerformanceCounter() - last_frame_end < sdl.SDL_GetPerformanceFrequency() / 10000) {
            continue;
        }

        defer last_frame_end = sdl.SDL_GetPerformanceCounter();

        const current_performance_ticks = sdl.SDL_GetPerformanceCounter() - start_tick;
        const current_time: f80 = @as(f80, @floatFromInt(current_performance_ticks)) / performance_frequency;

        const last_object_processed_before = state.last_processed_object;
        state.process(conductor.*, current_time);
        const last_object_processed_after = state.last_processed_object;

        for (last_object_processed_before..last_object_processed_after) |i| {
            const object = conductor.objects[i];
            if (object.obj_type == rhythm.Conductor.ObjectType.Note) {
                if (conductor.notes[object.index].type == .ln_tail) {
                    continue; // avoid playing the tail keysounds
                }
                const keysound_id = conductor.notes[object.index].keysound_id - 1;
                const keysound = conductor.keysounds[keysound_id];
                if (keysound != null) {
                    _ = ma.ma_sound_seek_to_pcm_frame(keysound, 0);
                    _ = ma.ma_sound_start(keysound);
                }
            }
        }
    }

    for (conductor.keysounds) |keysound| {
        if (keysound != null) {
            _ = ma.ma_sound_stop(keysound);
        }
    }
}
