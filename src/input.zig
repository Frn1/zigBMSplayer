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
    Miss,
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

const rating_process_order: [5]Rating = .{ .PerfectGreat, .Great, .Good, .Bad, .Poor };

fn processInput(
    current_time: Object.Time,
    timing_windows: []const TimingWindow,
    lane: Lane,
    objects: []const Object,
    object_seconds: []const Object.Time,
    last_pressed_indexes: []usize,
) ?Rating {
    const last_pressed_index = last_pressed_indexes[@intFromEnum(lane)];
    for (object_seconds[last_pressed_index..], objects[last_pressed_index..], last_pressed_index..) |obj_second, obj, i| {
        if (obj.hit(obj, lane) == false) {
            // Object is not hittable, move along...
            continue;
        }
        for (timing_windows, rating_process_order) |timing_window, rating| {
            if (current_time < obj_second and timing_window.early != null) {
                // hit is early
                const time_difference = obj_second - current_time;
                if (time_difference <= timing_window.early.?) {
                    last_pressed_indexes[@intFromEnum(lane)] = i;
                    std.debug.print("{d:.5} {d:.5} {}\n", .{ obj_second, current_time, rating });
                    return rating;
                }
            } else if (current_time >= obj_second and timing_window.late != null) {
                // hit is late
                const time_difference = current_time - obj_second;
                if (time_difference <= timing_window.late.?) {
                    last_pressed_indexes[@intFromEnum(lane)] = i;
                    std.debug.print("{d:.5} {d:.5} {}\n", .{ obj_second, current_time, rating });
                    return rating;
                }
            }
            // If we dont return, that means the object can't be hit
        }
        const last_timing_window = timing_windows[timing_windows.len - 1];
        if (last_timing_window.late != null) {
            const time_difference = current_time - obj_second;
            if (time_difference > last_timing_window.late.?) {
                last_pressed_indexes[@intFromEnum(lane)] = i;
                std.debug.print("{d:.5} {d:.5} {}\n", .{ obj_second, current_time, Rating.Miss });
                return .Miss; // Note has gotten outside of the hittable time range without being pressed
            }
        } else if (current_time < obj_second) {
            last_pressed_indexes[@intFromEnum(lane)] = i;
            std.debug.print("{d:.5} {d:.5} {}\n", .{ obj_second, current_time, Rating.Miss });
            return .Miss; // Same as above
        }
    }
    // Way too early to hit yet
    std.debug.print("{d:.5} null\n", .{current_time});
    return null;
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
    ratings: []Rating,
    object_seconds: []Object.Time,
    rank: Rank,
    start_tick: u64,
    input_stop_flag: *bool,
    quit_flag: *bool,
) !void {
    // how many ticks are in a second
    const performance_frequency: Object.Time = @floatFromInt(sdl.SDL_GetPerformanceFrequency());

    var last_pressed_indexes: [@typeInfo(Lane).Enum.fields.len]usize = .{0} ** @typeInfo(Lane).Enum.fields.len;
    var ratings: []usize = try allocator.alloc(Rating, objects.len);

    const rating_timing_windows = a: {
        var output: [5]TimingWindow = .{undefined} ** rating_process_order.len;
        for (rating_process_order, 0..) |rating, i| {
            output[i] = getTimingWindowForRating(rating, rank);
        }
        break :a output;
    };

    while (input_stop_flag.* == false) {
        const current_performance_ticks = sdl.SDL_GetPerformanceCounter() - start_tick;
        const current_time: Object.Time = @as(Object.Time, @floatFromInt(current_performance_ticks)) / performance_frequency;

        // handle events
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) > 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    quit_flag.* = true;
                },
                sdl.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    sdl.SDLK_LSHIFT, sdl.SDLK_LCTRL => _ = processInput(
                        current_time,
                        &rating_timing_windows,
                        .Scratch_P1,
                        objects,
                        object_seconds,
                        &last_pressed_indexes,
                    ),
                    sdl.SDLK_z => _ = processInput(
                        current_time,
                        &rating_timing_windows,
                        .White1_P1,
                        objects,
                        object_seconds,
                        &last_pressed_indexes,
                    ),
                    sdl.SDLK_s => _ = processInput(
                        current_time,
                        &rating_timing_windows,
                        .Black1_P1,
                        objects,
                        object_seconds,
                        &last_pressed_indexes,
                    ),
                    sdl.SDLK_x => _ = processInput(
                        current_time,
                        &rating_timing_windows,
                        .White2_P1,
                        objects,
                        object_seconds,
                        &last_pressed_indexes,
                    ),
                    sdl.SDLK_d => _ = processInput(
                        current_time,
                        &rating_timing_windows,
                        .Black2_P1,
                        objects,
                        object_seconds,
                        &last_pressed_indexes,
                    ),
                    sdl.SDLK_c => _ = processInput(
                        current_time,
                        &rating_timing_windows,
                        .White3_P1,
                        objects,
                        object_seconds,
                        &last_pressed_indexes,
                    ),
                    sdl.SDLK_f => _ = processInput(
                        current_time,
                        &rating_timing_windows,
                        .Black3_P1,
                        objects,
                        object_seconds,
                        &last_pressed_indexes,
                    ),
                    sdl.SDLK_v => _ = processInput(
                        current_time,
                        &rating_timing_windows,
                        .White4_P1,
                        objects,
                        object_seconds,
                        &last_pressed_indexes,
                    ),
                    else => {},
                },
                else => {},
            }
        }
    }
}
