const std = @import("std");

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_mixer.h");
    @cInclude("SDL2/SDL_ttf.h");
});
const sdl_utils = @import("sdl_utils.zig");

const c = @import("consts.zig");
const rhythm = @import("rhythm.zig");
const formats = @import("formats.zig");
const gfx = @import("graphics.zig");

pub fn main() !void {
    // Main allocator we use
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const main_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) @panic("Memory leak :(");
    }

    // init sdl
    try sdl_utils.sdlAssert(sdl.SDL_Init(
        @intCast(sdl.SDL_INIT_TIMER | sdl.SDL_INIT_AUDIO | sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_EVENTS),
    ) == 0);
    defer sdl.SDL_Quit();

    try sdl_utils.sdlAssert(sdl.TTF_Init() == 0);
    defer sdl.TTF_Quit();

    try sdl_utils.sdlAssert(sdl.Mix_Init(@intCast(sdl.MIX_INIT_OGG)) != 0);
    defer sdl.Mix_Quit();
    try sdl_utils.sdlAssert(sdl.Mix_OpenAudio(48000, sdl.MIX_DEFAULT_FORMAT, 2, 2048) == 0);
    defer sdl.Mix_CloseAudio();
    try sdl_utils.sdlAssert(sdl.Mix_AllocateChannels(1295) == 1295);

    var scroll_speed_mul: f80 = 2.0;

    var loading_arena = std.heap.ArenaAllocator.init(main_allocator);
    // Allocator used when loading stuff that wont stay after loading
    const loading_allocator = loading_arena.allocator();

    const args = try std.process.argsAlloc(loading_allocator);
    if (args.len < 2) {
        std.log.err("ERROR: Missing path\n", .{});
        std.process.exit(1);
        return error.ExpectedArgument;
    }

    // Path for the chart file
    const chart_file_path = std.fs.realpathAlloc(loading_allocator, args[1]) catch |e| {
        std.log.err("ERROR: Couldn't parse path ({!})\n", .{e});
        std.process.exit(1);
        return e;
    };

    // Path for the song folder
    const song_folder_path = std.fs.path.dirname(args[1]) orelse try std.process.getCwdAlloc(loading_allocator);

    const chart_file = std.fs.openFileAbsolute(chart_file_path, std.fs.File.OpenFlags{}) catch |e| {
        std.log.err("ERROR: Couldn't open file ({!})\n", .{e});
        std.process.exit(1);
        return e;
    };
    defer chart_file.close();

    // TODO: Multiple conductors/timing groups???
    var conductor = formats.compileBMS(
        main_allocator,
        song_folder_path,
        try chart_file.readToEndAllocOptions(
            loading_allocator,
            2048 * 2048,
            64 * 2048,
            1,
            0,
        ),
    ) catch |e| {
        std.log.err("ERROR: Couldn't load BMS File ({!})", .{e});
        std.process.exit(1);
    };
    // Make sure to unload the keysounds
    defer for (conductor.keysounds) |sound| {
        sdl.Mix_FreeChunk(sound);
    };
    // Make sure to free the chart data
    defer main_allocator.free(conductor.notes);
    defer main_allocator.free(conductor.segments);

    // Free everything in the loading arena
    // YEAH I KNOW I should be doing this with defer
    // the next line after creating the arena but shut
    loading_arena.deinit();

    // Create objects for the conductor
    try conductor.createObjects(main_allocator);
    defer conductor.deleteObjects(main_allocator);

    // Calculate time we hit every object
    const times = try conductor.calculateObjectTimesInSeconds(main_allocator);
    defer main_allocator.free(times);
    // Calculate position we hit every object
    const positions = try conductor.calculateVisualBeats(main_allocator);
    defer main_allocator.free(positions);

    // SDL window
    const window: *sdl.SDL_Window = sdl.SDL_CreateWindow(
        "Zig BMS Player",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        c.screen_width,
        c.screen_height,
        sdl.SDL_WINDOW_RESIZABLE,
    ).?;
    defer sdl.SDL_DestroyWindow(window);

    // SDL renderer
    const renderer: *sdl.SDL_Renderer = sdl.SDL_CreateRenderer(
        window,
        -1,
        sdl.SDL_RENDERER_ACCELERATED,
    ).?;
    defer sdl.SDL_DestroyRenderer(renderer);

    const debug_font: *sdl.TTF_Font = sdl.TTF_OpenFont("fonts/RobotoMono.ttf", 24).?;
    defer sdl.TTF_CloseFont(debug_font);

    var state = rhythm.ConductorState{};

    // how many ticks are in a second
    const performance_frequency: f80 = @floatFromInt(sdl.SDL_GetPerformanceFrequency());

    // the start of the performance tick counter
    const start_tick = sdl.SDL_GetPerformanceCounter();

    // used for fps
    var last_frame_end = sdl.SDL_GetPerformanceCounter();

    // Event loop
    main_loop: while (true) {
        // We dont care about "strictness" or "accuracy"
        // we just want something that runs quick lol
        // @setFloatMode(std.builtin.FloatMode.optimized);

        var frame_arena = std.heap.ArenaAllocator.init(main_allocator);
        defer frame_arena.deinit();
        const frame_allocator = frame_arena.allocator();

        // current sdl performance tick (with start_performance_ticks already subtracted)
        const current_performance_ticks = sdl.SDL_GetPerformanceCounter() - start_tick;
        const current_time: f80 = @as(f80, @floatFromInt(current_performance_ticks)) / performance_frequency;

        // update game state
        const last_object_processed_before = state.last_processed_object;
        state.process(conductor, current_time);
        const last_object_processed_after = state.last_processed_object;

        if (state.last_processed_object == conductor.objects.len - 1) {
            if (sdl.Mix_Playing(-1) == 0) { // wait until all sounds stop to quit
                break; // Quit the program
            } else {
                for (0..1295) |channel| {
                    if (sdl.Mix_Playing(@intCast(channel)) != 0 and sdl.Mix_Volume(@intCast(channel), -1) != 0) {
                        break; // If a sound is still playing (and has volume), break
                    }
                } else {
                    break :main_loop; // Quit the program
                }
            }
        }

        const visual_beat = state.calculateVisualPosition(state.current_beat);

        for (last_object_processed_before..last_object_processed_after) |i| {
            const object = conductor.objects[i];
            if (object.obj_type == rhythm.Conductor.ObjectType.Note) {
                if (conductor.notes[object.index].type == .ln_tail) {
                    continue; // avoid playing the tail keysounds
                }
                const keysound_id = conductor.notes[object.index].keysound_id - 1;
                const keysound = conductor.keysounds[keysound_id];
                if (keysound != null) {
                    _ = sdl.Mix_Volume(keysound_id, sdl.SDL_MIX_MAXVOLUME);
                    try sdl_utils.sdlAssert(sdl.Mix_PlayChannel(keysound_id, conductor.keysounds[keysound_id], 0) == keysound_id);
                }
            }
        }

        // handle events
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) > 0) {
            switch (event.type) {
                sdl.SDL_QUIT => break :main_loop,
                sdl.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    sdl.SDLK_UP => scroll_speed_mul += 0.1,
                    sdl.SDLK_DOWN => scroll_speed_mul -= 0.1,
                    else => {},
                },
                else => {},
            }
        }

        defer sdl.SDL_RenderPresent(renderer);
        defer last_frame_end = sdl.SDL_GetPerformanceCounter();

        try sdl_utils.sdlAssert(sdl.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xFF) == 0);
        try sdl_utils.sdlAssert(sdl.SDL_RenderClear(renderer) == 0);

        // Draw barlines BEFORE notes so they appear behind the notes
        for (conductor.objects, positions, 0..) |object, position, i| {
            var render_y = @as(i32, @intFromFloat((visual_beat - position.visual_beat) * scroll_speed_mul * c.beat_height));
            render_y += c.judgement_line_y;

            if (render_y < -c.note_height) {
                continue;
            }

            if (object.obj_type == .Segment) {
                if (render_y > c.screen_height + c.note_height) {
                    continue;
                }

                // change color to white
                try sdl_utils.sdlAssert(sdl.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF) == 0);

                const segment = conductor.segments[conductor.objects[i].index];
                switch (segment.type) {
                    .barline => {
                        try sdl_utils.sdlAssert(sdl.SDL_RenderDrawLine(renderer, 0, render_y, c.note_width * 8, render_y) == 0);
                    },
                    else => {},
                }
            }
        }

        // And NOW we draw the notes
        for (conductor.objects, positions, 0..) |object, position, i| {
            var render_y = @as(i32, @intFromFloat((visual_beat - position.visual_beat) * scroll_speed_mul * c.beat_height));
            render_y += c.judgement_line_y;

            if (render_y < -c.note_height) {
                continue;
            }

            if (object.obj_type == rhythm.Conductor.ObjectType.Note) {
                const note = conductor.notes[conductor.objects[i].index];

                const lane = switch (note.lane) {
                    0...4 => note.lane + 1, // First 5 keys for 5k+1
                    5 => 0, // Scratch
                    else => note.lane - 1, // the other extra lanes for 7k+1 (i do not know why its like this... but i didnt make BMS so i dont wanna hear it)
                };

                var render_x = @as(i32, lane);
                render_x *= c.note_width;

                // change color to red
                try sdl_utils.sdlAssert(sdl.SDL_SetRenderDrawColor(renderer, 0xFF, 0x00, 0x00, 0xFF) == 0);

                switch (note.type) {
                    .normal => {
                        if (render_y > c.screen_height + c.note_height) {
                            continue;
                        }

                        switch (note.type.normal) {
                            .normal => {
                                // change color to red
                                try sdl_utils.sdlAssert(sdl.SDL_SetRenderDrawColor(renderer, 0xFF, 0x00, 0x00, 0xFF) == 0);
                            },
                            .mine => {
                                // change color to yellow
                                try sdl_utils.sdlAssert(sdl.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0x00, 0xFF) == 0);
                            },
                            .hidden => {
                                // change color to blue
                                try sdl_utils.sdlAssert(sdl.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0xFF, 0xFF) == 0);
                            },
                        }

                        const note_rect: sdl.SDL_Rect = sdl.SDL_Rect{
                            .x = render_x,
                            .y = render_y - c.note_height,
                            .w = c.note_width,
                            .h = c.note_height,
                        };
                        try sdl_utils.sdlAssert(sdl.SDL_RenderFillRect(renderer, &note_rect) == 0);
                    },
                    .ln_head => {
                        var tail_render_y = @as(i32, @intFromFloat(
                            (visual_beat - positions[position.ln_tail_obj_index.?].visual_beat) * scroll_speed_mul * c.beat_height,
                        ));
                        tail_render_y += c.judgement_line_y;
                        if (tail_render_y > c.screen_height + c.note_height) {
                            continue;
                        }
                        const note_rect: sdl.SDL_Rect = sdl.SDL_Rect{
                            .x = render_x,
                            .y = tail_render_y,
                            .w = c.note_width,
                            .h = render_y - tail_render_y,
                        };
                        try sdl_utils.sdlAssert(sdl.SDL_RenderFillRect(renderer, &note_rect) == 0);
                    },
                    else => {},
                }
            }
        }

        // change color to white
        try sdl_utils.sdlAssert(sdl.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF) == 0);
        try sdl_utils.sdlAssert(sdl.SDL_RenderDrawLine(renderer, 0, c.judgement_line_y, c.note_width * 8, c.judgement_line_y) == 0);

        // draw text used for debuging
        const text: [:0]u8 = try frame_allocator.allocSentinel(u8, 64, 0);

        _ = try std.fmt.bufPrint(text, "B   {d:.3}   {d:.3}\u{0000}", .{ state.current_beat, 60.0 / state.current_sec_per_beat });

        try gfx.drawText(text, renderer, 0, 24 * 0, debug_font);

        _ = try std.fmt.bufPrint(text, "VB  {d:.3}  x{d:.3}\u{0000}", .{ visual_beat, state.current_scroll_mul });
        try gfx.drawText(text, renderer, 0, 24 * 1, debug_font);

        _ = try std.fmt.bufPrint(text, "FPS {d:.3}\u{0000}", .{performance_frequency / @as(
            f80,
            @floatFromInt(sdl.SDL_GetPerformanceCounter() - last_frame_end),
        )});
        try gfx.drawText(text, renderer, 0, 24 * 2, debug_font);

        _ = try std.fmt.bufPrint(text, "SC  {d:.1}\u{0000}", .{scroll_speed_mul});
        try gfx.drawText(text, renderer, 0, 24 * 3, debug_font);
    }
}
