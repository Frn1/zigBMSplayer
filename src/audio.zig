const std = @import("std");

const ma = @cImport({
    @cDefine("MINIAUDIO_IMPLEMENTATION", {});
    @cInclude("miniaudio.h");
});

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const Conductor = @import("rhythm/conductor.zig").Conductor;
const utils = @import("utils.zig");

pub fn audioThread(conductor: *Conductor, object_times: []f80, start_tick: u64, audio_stop_flag: *bool) void {
    _ = conductor;
    _ = object_times;
    _ = start_tick;
    _ = audio_stop_flag;
    // defer for (conductor.keysounds) |keysound| {
    //     if (keysound != null) {
    //         _ = ma.ma_sound_stop(keysound);
    //     }
    // };

    // // how many ticks are in a second
    // const performance_frequency: f80 = @floatFromInt(sdl.SDL_GetPerformanceFrequency());

    // var last_frame_end = sdl.SDL_GetPerformanceCounter();

    // var next_object_to_play: usize = 0;

    // while (audio_stop_flag.* == false) {
    //     if (sdl.SDL_GetPerformanceCounter() - last_frame_end < sdl.SDL_GetPerformanceFrequency() / 10000) {
    //         continue;
    //     }

    //     defer last_frame_end = sdl.SDL_GetPerformanceCounter();

    //     const current_performance_ticks = sdl.SDL_GetPerformanceCounter() - start_tick;
    //     const current_time: f80 = @as(f80, @floatFromInt(current_performance_ticks)) / performance_frequency;

    //     for (next_object_to_play..conductor.objects.len) |i| {
    //         if (current_time >= object_times[i]) {
    //             defer next_object_to_play = i + 1;
    //             std.debug.print("{d}\n", .{i});
    //             const object = conductor.objects[i];
    //             if (object.obj_type == .Note) {
    //                 if (conductor.notes[object.index].type == .ln_tail) {
    //                     continue; // avoid playing the ln tail keysounds
    //                 }
    //                 // if (conductor.notes[object.index].type == .normal) {
    //                 //     if (conductor.notes[object.index].type.normal != .normal) {
    //                 //         continue; // avoid playing mines and the hidden keysounds
    //                 //     }
    //                 // }
    //                 const keysound_id = conductor.notes[object.index].keysound_id - 1;
    //                 const keysound = conductor.keysounds[keysound_id];
    //                 if (keysound != null) {
    //                     _ = ma.ma_sound_stop(keysound);
    //                     _ = ma.ma_sound_seek_to_pcm_frame(keysound, 0);
    //                     _ = ma.ma_sound_start(keysound);
    //                 }
    //             }
    //         } else {
    //             break;
    //         }
    //     }
    // }
}
