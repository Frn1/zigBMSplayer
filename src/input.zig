const std = @import("std");

const ma = @cImport({
    @cDefine("MINIAUDIO_IMPLEMENTATION", {});
    @cInclude("miniaudio.h");
});

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const utils = @import("utils.zig");

const Conductor = @import("rhythm/conductor.zig");
const Rank = @import("rhythm/conductor.zig").Rank;
const Object = @import("rhythm/object.zig").Object;
const Lane = @import("rhythm/objects/note.zig").Lane;

pub const Rating = enum {
    PerfectGreat,
    Great,
    Good,
    Bad,
    Poor,
};

const TimingWindow = struct { late: ?Object.Time, early: ?Object.Time };

fn getTimingWindowForRating(rating: Rating, rank: Rank) TimingWindow {
    return switch (rank) {
        .easy => switch (rating) {
            .PerfectGreat => .{ .late = 0.021, .early = 0.021 },
            .Great => .{ .late = 0.060, .early = 0.060 },
            .Good => .{ .late = 0.120, .early = 0.120 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null }, // Excessive poors can only occur later, never earlier
            .Miss => .{ .late = null, .early = null },
        },
        .normal => switch (rating) {
            .PerfectGreat => .{ .late = 0.018, .early = 0.018 },
            .Great => .{ .late = 0.040, .early = 0.040 },
            .Good => .{ .late = 0.100, .early = 0.100 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null },
            .Miss => .{ .late = null, .early = null },
        },
        .hard => switch (rating) {
            .PerfectGreat => .{ .late = 0.015, .early = 0.015 },
            .Great => .{ .late = 0.030, .early = 0.030 },
            .Good => .{ .late = 0.060, .early = 0.060 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null },
            .Miss => .{ .late = null, .early = null },
        },
        .very_hard => switch (rating) {
            .PerfectGreat => .{ .late = 0.008, .early = 0.008 },
            .Great => .{ .late = 0.024, .early = 0.024 },
            .Good => .{ .late = 0.040, .early = 0.040 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null },
            .Miss => .{ .late = null, .early = null },
        },
    };
}

const rating_process_order = .{ .PerfectGreat, .Great, .Good, .Bad, .Poor, .Miss };

fn processInput(
    current_time: Object.Time,
    rank: Rank,
    lane: Lane,
    objects: []Object,
    object_times: []Object.Time,
    last_pressed_index: *usize,
) ?Rating {
    const rating_timing_windows = {
        var output: []TimingWindow = .{undefined} ** rating_process_order.len;
        for (rating_process_order, 0..) |rating, i| {
            output[i] = getTimingWindowForRating(rating, rank);
        }
        output;
    };

    return objects_loop: for (object_times[last_pressed_index..], last_pressed_index..) |object_time, i| {
        const last_timing_window = rating_timing_windows[rating_timing_windows.len - 1];
        if (last_timing_window.early != null) {
            if (object_time - current_time > last_timing_window.early.?) {
                break :objects_loop null;
            }
        }
        if (last_timing_window.late != null) {
            if (current_time - object_time > last_timing_window.late.?) {
                break :objects_loop .Miss;
            }
        }
        for (rating_process_order, rating_timing_windows) |rating, timing_window| {
            if (objects[i].hit(lane)) {
                if (timing_window.early != null) {
                    if (object_time - current_time < timing_window.early.?) {
                        last_pressed_index.* = i;
                        break :objects_loop rating;
                    }
                }
                if (timing_window.late != null) {
                    if (current_time - object_time < timing_window.late.?) {
                        last_pressed_index.* = i;
                        break :objects_loop rating;
                    }
                }
            }
        }
    };
}

fn playNextKeysound(
    lane: Lane,
    objects: []Object,
    last_pressed_index: usize,
) void {
    for (last_pressed_index..objects.len) |i| {
        if (objects[i].hit(lane)) {
            break;
        }
    }
}

pub fn inputThread(
    objects: []Object,
    object_times: []Object.Time,
    rank: Rank,
    start_tick: u64,
    input_stop_flag: *bool,
    quit_flag: *bool,
) void {
    _ = object_times;
    _ = rank;
    // how many ticks are in a second
    const performance_frequency: f80 = @floatFromInt(sdl.SDL_GetPerformanceFrequency());

    const last_pressed_index = 0;

    const current_performance_ticks = sdl.SDL_GetPerformanceCounter() - start_tick;
    const current_time: f80 = @as(f80, @floatFromInt(current_performance_ticks)) / performance_frequency;
    _ = current_time;

    while (input_stop_flag == false) {
        // handle events
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) > 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    quit_flag.* = true;
                    return;
                },
                sdl.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    sdl.SDLK_z => playNextKeysound(Lane.White1_P1, objects, last_pressed_index),
                    else => {},
                },
                else => {},
            }
        }
    }
}
