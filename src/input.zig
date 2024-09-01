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

pub const Judgement = enum {
    PerfectGreat,
    Great,
    Good,
    Bad,
    Poor,
    Miss,
};

const TimingWindow = struct { late: ?Object.Time, early: ?Object.Time };

fn getTimingWindowForJudgement(judgement: Judgement, rank: Rank) TimingWindow {
    return switch (rank) {
        .easy => switch (judgement) {
            .PerfectGreat => .{ .late = 0.021, .early = 0.021 },
            .Great => .{ .late = 0.060, .early = 0.060 },
            .Good => .{ .late = 0.120, .early = 0.120 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null }, // Excessive poors can only occur later, never earlier
            .Miss => .{ .late = null, .early = null },
        },
        .normal => switch (judgement) {
            .PerfectGreat => .{ .late = 0.018, .early = 0.018 },
            .Great => .{ .late = 0.040, .early = 0.040 },
            .Good => .{ .late = 0.100, .early = 0.100 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null },
            .Miss => .{ .late = null, .early = null },
        },
        .hard => switch (judgement) {
            .PerfectGreat => .{ .late = 0.015, .early = 0.015 },
            .Great => .{ .late = 0.030, .early = 0.030 },
            .Good => .{ .late = 0.060, .early = 0.060 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null },
            .Miss => .{ .late = null, .early = null },
        },
        .very_hard => switch (judgement) {
            .PerfectGreat => .{ .late = 0.008, .early = 0.008 },
            .Great => .{ .late = 0.024, .early = 0.024 },
            .Good => .{ .late = 0.040, .early = 0.040 },
            .Bad => .{ .late = 0.200, .early = 0.200 },
            .Poor => .{ .late = 1.000, .early = null },
            .Miss => .{ .late = null, .early = null },
        },
    };
}

const judgment_process_order: [5]Judgement = .{ .PerfectGreat, .Great, .Good, .Bad, .Poor };

fn playNextKeysound(
    lane: Lane,
    objects: []const Object,
    last_pressed_index: usize,
) void {
    for (last_pressed_index..objects.len) |i| {
        if (objects[i].canHit(lane)) {
            break;
        }
    }
}

fn pressLane(
    arena_allocator: std.mem.Allocator,
    lane: Lane,
    objects: []const Object,
    object_seconds: []const Object.Time,
    current_time: Object.Time,
    timing_windows: []const TimingWindow,
    judgements: []?Judgement,
) !void {
    var hittable_indexes = try arena_allocator.alloc(usize, 0);

    get_objects: for (
        objects,
        object_seconds,
        0..,
    ) |
        object,
        time,
        index,
    | {
        if (object.canHit(object, lane) == false) {
            continue;
        }
        for (timing_windows) |timing_window| {
            if (timing_window.early != null and
                time - current_time <= timing_window.early.? and
                time - current_time >= 0)
            {
                // Object is early
                hittable_indexes = try arena_allocator.realloc(
                    hittable_indexes,
                    hittable_indexes.len + 1,
                );
                hittable_indexes[hittable_indexes.len - 1] = index;
                continue :get_objects;
            } else if (timing_window.late != null and
                current_time - time <= timing_window.late.? and
                current_time - time >= 0)
            {
                // Object is late
                hittable_indexes = try arena_allocator.realloc(
                    hittable_indexes,
                    hittable_indexes.len + 1,
                );
                hittable_indexes[hittable_indexes.len - 1] = index;
                continue :get_objects;
            } else if ((timing_window.early != null and
                time - current_time > timing_window.early.?) and
                (timing_window.late != null and
                current_time - time > timing_window.late.?))
            {
                break :get_objects;
            }
        }
    }

    for (hittable_indexes) |index| {
        if (judgements[index] != null) {
            const time = object_seconds[index];

            for (judgment_process_order, timing_windows) |
                judgement,
                timing_window,
            | {
                if (timing_window.early != null and
                    time - current_time <= timing_window.early.?)
                {
                    // Object is early
                    judgements[index] = judgement;
                } else if (timing_window.late != null and
                    current_time - time <= timing_window.late.?)
                {
                    // Object is late
                    judgements[index] = judgement;
                }
            }
            objects[index].hit(objects[index]);
            return;
        }
    }

    // try to rehit notes
    for (hittable_indexes) |index| {
        const time = object_seconds[index];

        for (judgment_process_order, timing_windows) |
            judgement,
            timing_window,
        | {
            if (timing_window.early != null and
                time - current_time <= timing_window.early.?)
            {
                // Object is early
                judgements[index] = judgement;
            } else if (timing_window.late != null and
                current_time - time <= timing_window.late.?)
            {
                // Object is late
                judgements[index] = judgement;
            }
        }
        objects[index].hit(objects[index]);
        return;
    }

    for (
        objects,
        object_seconds,
    ) |
        object,
        time,
    | {
        if (object.canHit(object, lane) == false) {
            continue;
        }

        if (time > current_time) {
            object.hit(object);
            break;
        }
    }
}

pub fn inputThread(
    allocator: std.mem.Allocator,
    objects: []const Object,
    judgements: []?Judgement,
    object_seconds: []const Object.Time,
    rank: Rank,
    start_tick: u64,
    input_stop_flag: *bool,
    quit_flag: *bool,
) !void {
    // how many ticks are in a second
    const performance_frequency: Object.Time = @floatFromInt(sdl.SDL_GetPerformanceFrequency());

    // var last_pressed_indexes: [@typeInfo(Lane).Enum.fields.len]usize =
    //     .{0} ** @typeInfo(Lane).Enum.fields.len;

    const judgement_timing_windows = a: {
        var output: [judgment_process_order.len]TimingWindow = .{undefined} ** judgment_process_order.len;
        for (judgment_process_order, 0..) |judgement, i| {
            output[i] = getTimingWindowForJudgement(judgement, rank);
        }
        break :a output;
    };

    while (input_stop_flag.* == false) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const arena_allocator = arena.allocator();

        const current_performance_ticks = sdl.SDL_GetPerformanceCounter() - start_tick;
        const current_time: Object.Time = @as(
            Object.Time,
            @floatFromInt(current_performance_ticks),
        ) / performance_frequency;

        // handle events
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) > 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    quit_flag.* = true;
                },
                sdl.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    sdl.SDLK_LSHIFT, sdl.SDLK_LCTRL => try pressLane(
                        arena_allocator,
                        Lane.Scratch_P1,
                        objects,
                        object_seconds,
                        current_time,
                        &judgement_timing_windows,
                        judgements,
                    ),
                    sdl.SDLK_z => try pressLane(
                        arena_allocator,
                        Lane.White1_P1,
                        objects,
                        object_seconds,
                        current_time,
                        &judgement_timing_windows,
                        judgements,
                    ),
                    sdl.SDLK_s => try pressLane(
                        arena_allocator,
                        Lane.Black1_P1,
                        objects,
                        object_seconds,
                        current_time,
                        &judgement_timing_windows,
                        judgements,
                    ),
                    sdl.SDLK_x => try pressLane(
                        arena_allocator,
                        Lane.White2_P1,
                        objects,
                        object_seconds,
                        current_time,
                        &judgement_timing_windows,
                        judgements,
                    ),
                    sdl.SDLK_d => try pressLane(
                        arena_allocator,
                        Lane.Black2_P1,
                        objects,
                        object_seconds,
                        current_time,
                        &judgement_timing_windows,
                        judgements,
                    ),
                    sdl.SDLK_c => try pressLane(
                        arena_allocator,
                        Lane.White3_P1,
                        objects,
                        object_seconds,
                        current_time,
                        &judgement_timing_windows,
                        judgements,
                    ),
                    sdl.SDLK_f => try pressLane(
                        arena_allocator,
                        Lane.Black3_P1,
                        objects,
                        object_seconds,
                        current_time,
                        &judgement_timing_windows,
                        judgements,
                    ),
                    sdl.SDLK_v => try pressLane(
                        arena_allocator,
                        Lane.White4_P1,
                        objects,
                        object_seconds,
                        current_time,
                        &judgement_timing_windows,
                        judgements,
                    ),
                    else => {},
                },
                else => {},
            }
        }
    }
}
