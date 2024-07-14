const std = @import("std");

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_mixer.h");
    @cInclude("SDL2/SDL_ttf.h");
});

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
    try std.testing.expect(
        sdl.SDL_Init(
            @intCast(sdl.SDL_INIT_TIMER | sdl.SDL_INIT_AUDIO | sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_EVENTS),
        ) == 0,
    );
    defer sdl.SDL_Quit();

    try std.testing.expect(sdl.TTF_Init() == 0);
    defer sdl.TTF_Quit();

    try std.testing.expect(sdl.Mix_Init(@intCast(sdl.MIX_INIT_OGG)) != 0);
    defer sdl.Mix_Quit();
    try std.testing.expect(sdl.Mix_OpenAudio(48000, sdl.MIX_DEFAULT_FORMAT, 2, 2048) == 0);
    defer sdl.Mix_CloseAudio();
    try std.testing.expect(sdl.Mix_AllocateChannels(1295) == 1295);

    var scroll_speed_mul: f80 = 2.0;

    var loading_arena = std.heap.ArenaAllocator.init(main_allocator);
    // Allocator used when loading stuff that wont stay after loading
    const loading_allocator = loading_arena.allocator();

    // Current working directory path
    const cwd_path = try std.process.getCwdAlloc(loading_allocator);

    // Path for the song folder
    const song_folder_path = try std.fs.path.join(loading_allocator, &[_][]const u8{
        cwd_path,
        "test_chart",
        "[Clue]Random",
        // "[pi26]Hypersurface",
        // "Anhedonia",
    });

    // Path for the chart file
    const chart_file_path = try std.fs.path.join(loading_allocator, &[_][]const u8{
        song_folder_path,
        // "ass.bms",
        "_random_s2.bms",
        // "7MX.bms",
        // "anhedonia_XYZ.bms",
    });

    const chart_file = try std.fs.openFileAbsolute(chart_file_path, std.fs.File.OpenFlags{});
    defer chart_file.close();

    // TODO: Multiple conductors/timing groups???
    var conductor = try formats.compileBMS(
        main_allocator,
        song_folder_path,
        try chart_file.readToEndAllocOptions(
            loading_allocator,
            2048 * 2048,
            64 * 2048,
            1,
            0,
        ),
    );
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
        @setFloatMode(std.builtin.FloatMode.optimized);

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

        const visual_beat = state.calculateVisualPosition(state.current_beat);

        for (last_object_processed_before..last_object_processed_after) |i| {
            const object = conductor.objects[i];
            if (object.obj_type == rhythm.Conductor.ObjectType.Note) {
                const keysound_id = conductor.notes[object.index].keysound_id - 1;
                const keysound = conductor.keysounds[keysound_id];
                if (keysound != null) {
                    try std.testing.expect(sdl.Mix_PlayChannel(keysound_id, conductor.keysounds[keysound_id], 0) == keysound_id);
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
        try std.testing.expect(sdl.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xFF) == 0);
        try std.testing.expect(sdl.SDL_RenderClear(renderer) == 0);

        // Draw barlines BEFORE notes so they appear behind the notes
        for (conductor.objects, positions, 0..) |object, position, i| {
            var render_y = @as(i32, @intFromFloat((visual_beat - position.visual_beat) * scroll_speed_mul * c.beat_height));
            render_y += c.judgement_line_y;

            if (render_y < -c.note_height) {
                continue;
            }

            if (object.obj_type == rhythm.Conductor.ObjectType.Segment) {
                if (render_y > c.screen_height + c.note_height) {
                    continue;
                }

                // change color to white
                try std.testing.expect(sdl.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF) == 0);

                const segment = conductor.segments[conductor.objects[i].index];
                switch (segment.type) {
                    rhythm.SegmentTypeTag.barline => {
                        try std.testing.expect(sdl.SDL_RenderDrawLine(renderer, 0, render_y, c.note_width * 9, render_y) == 0);
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

                var render_x = @as(i32, note.lane);
                render_x *= c.note_width;

                // change color to red
                try std.testing.expect(sdl.SDL_SetRenderDrawColor(renderer, 0xFF, 0x00, 0x00, 0xFF) == 0);

                switch (note.type) {
                    rhythm.NoteTypeTag.normal => {
                        if (render_y > c.screen_height + c.note_height) {
                            continue;
                        }

                        const note_rect: sdl.SDL_Rect = sdl.SDL_Rect{
                            .x = render_x,
                            .y = render_y - c.note_height,
                            .w = c.note_width,
                            .h = c.note_height,
                        };
                        try std.testing.expect(sdl.SDL_RenderFillRect(renderer, &note_rect) == 0);
                    },
                    rhythm.NoteTypeTag.ln_head => {
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
                        try std.testing.expect(sdl.SDL_RenderFillRect(renderer, &note_rect) == 0);
                    },
                    else => {},
                }
            }
        }

        // change color to white
        try std.testing.expect(sdl.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF) == 0);
        try std.testing.expect(sdl.SDL_RenderDrawLine(renderer, 0, c.judgement_line_y, c.note_width * 9, c.judgement_line_y) == 0);

        // draw text used for debuging
        const text: [:0]u8 = try frame_allocator.allocSentinel(u8, 64, 0);

        _ = try std.fmt.bufPrint(text, "B   {d:.3}   {d:.3}\u{0000}", .{ state.current_beat, 60.0 / state.current_sec_per_beat });

        try gfx.draw_text(text, renderer, 0, 24 * 0, debug_font);

        _ = try std.fmt.bufPrint(text, "VB  {d:.3}  x{d:.3}\u{0000}", .{ visual_beat, state.current_scroll_mul });
        try gfx.draw_text(text, renderer, 0, 24 * 1, debug_font);

        _ = try std.fmt.bufPrint(text, "FPS {d:.3}\u{0000}", .{performance_frequency / @as(
            f80,
            @floatFromInt(sdl.SDL_GetPerformanceCounter() - last_frame_end),
        )});
        try gfx.draw_text(text, renderer, 0, 24 * 2, debug_font);

        _ = try std.fmt.bufPrint(text, "SC  {d:.1}\u{0000}", .{scroll_speed_mul});
        try gfx.draw_text(text, renderer, 0, 24 * 3, debug_font);
    }
}
