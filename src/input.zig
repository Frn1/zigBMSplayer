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
const Object = @import("rhythm/object.zig").Object;

pub const Rating = enum { PerfectGreat, Great, Good, Bad, Poor };

fn getTimingWindowForRating(rating: Rating, rank: Conductor.Rank) struct { late: ?Object.Time, early: ?Object.Time } {
    return switch (rank) {
        .easy => switch (rating) {
            .PerfectGreat => .{ .late = 0.021, .early = 0.021 },
            .Great => .{ .late = 0.060, .early = 0.060 },
            .Good => .{ .late = 0.120, .early = 0.120 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null }, // Excessive poors can only occur later, never earlier
        },
        .normal => switch (rating) {
            .PerfectGreat => .{ .late = 0.018, .early = 0.018 },
            .Great => .{ .late = 0.040, .early = 0.040 },
            .Good => .{ .late = 0.100, .early = 0.100 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null },
        },
        .hard => switch (rating) {
            .PerfectGreat => .{ .late = 0.015, .early = 0.015 },
            .Great => .{ .late = 0.030, .early = 0.030 },
            .Good => .{ .late = 0.060, .early = 0.060 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null },
        },
        .very_hard => switch (rating) {
            .PerfectGreat => .{ .late = 0.008, .early = 0.008 },
            .Great => .{ .late = 0.024, .early = 0.024 },
            .Good => .{ .late = 0.040, .early = 0.040 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null },
        },
    };
}

pub fn inputThread(object_times: []Object.Time, rank: Rank, start_tick: u64, input_stop_flag: *bool, quit_flag: *bool) void {
    // how many ticks are in a second
    const performance_frequency: f80 = @floatFromInt(sdl.SDL_GetPerformanceFrequency());

    var last_frame_end = sdl.SDL_GetPerformanceCounter();

    var last_object_index = 0;

    for (object_times)
}
