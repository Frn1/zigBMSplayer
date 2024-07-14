const std = @import("std");

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_mixer.h");
});

const c = @import("consts.zig");
const rhythm = @import("rhythm.zig");
const formats = @import("formats.zig");
const gfx = @import("graphics.zig");

pub fn main() !void {
    // Main allocator we use
    const main_allocator = std.heap.page_allocator;

    // const scroll_speed_mul: f80 = 2.5;

    var loading_arena = std.heap.ArenaAllocator.init(main_allocator);
    // Yes we already do this after compiling the charts but
    // its better to make sure to free everything in the loading arena
    defer loading_arena.deinit();
    // Allocator used when loading files
    const loading_allocator = loading_arena.allocator();

    // Current working directory path
    const cwdPath = try std.process.getCwdAlloc(loading_allocator);

    // Path for the song folder
    const song_folder_path = try std.fs.path.join(loading_allocator, &[_][]const u8{
        cwdPath,
        "test_chart",
        "[Clue]Random",
        // "[pi26]Hypersurface",
        // "Anhedonia",
    });

    // Path for the chart file
    const chart_file_path = try std.fs.path.join(loading_allocator, &[_][]const u8{
        song_folder_path,
        // "ass2.bms",
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
        sdl.Mix_FreeMusic(sound);
    };

    // Free everything in the loading arena
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
    const window: ?*sdl.SDL_Window = sdl.SDL_CreateWindow(
        "hiiiii",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        c.screen_width,
        c.screen_height,
        sdl.SDL_WINDOW_RESIZABLE,
    );
    defer sdl.SDL_DestroyWindow(window);

    // SDL renderer
    const renderer: ?*sdl.SDL_Renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED);
    defer sdl.SDL_DestroyRenderer(renderer);

    defer sdl.SDL_Quit();

    var quit = false;

    // Rect used for the notes
    var note_rect: sdl.SDL_Rect = sdl.SDL_Rect{
        .w = c.note_width,
        .h = c.note_height,
    };

    // Square position: In the middle of the screen
    // note_rect.x = 800 / 2 - @divFloor(note_rect.w, 2);
    // note_rect.y = 600 / 2 - @divFloor(note_rect.h, 2);

    // Event loop
    while (!quit) {
        var frame_arena = std.heap.ArenaAllocator.init(main_allocator);
        defer frame_arena.deinit();
        // const frame_allocator = frame_arena.allocator();

        const text1: [:0]u8 = try frame_arena.allocSentinel(u8, 64, 0);
        const text2: [:0]u8 = try frame_arena.allocSentinel(u8, 64, 0);

        _ = text1;
        _ = text2;

        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            if (event.type == sdl.SDL_QUIT) {
                quit = true;
            }
        }
        std.debug.assert(sdl.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xFF) == 0);
        std.debug.assert(sdl.SDL_RenderClear(renderer) == 0);
        std.debug.assert(sdl.SDL_SetRenderDrawColor(renderer, 0xFF, 0x00, 0x00, 0xFF) == 0);
        std.debug.assert(sdl.SDL_RenderFillRect(renderer, &note_rect) == 0);

        defer sdl.SDL_RenderPresent(renderer);
    }

    // var timer = try std.time.Timer.start();
    // var current_ns: uint = @as(uint, @intCast(timer.read()));

    // var current_ns: uint = @as(uint, @intFromFloat(raylib.GetTime() * 1e+9));

    // var current_ns: c.uint = 0;

    // var current_ns: c.uint = 0;

    // var state = rhythm.ConductorState{};

    // while (!raylib.WindowShouldClose()) {
    //     // const screen_height = raylib.GetScreenHeight();
    //     raylib.BeginDrawing();
    //     defer raylib.EndDrawing();

    //     // const new_current_ns = @as(uint, @intCast(timer.read()));
    //     // const new_current_ns = @as(uint, @intFromFloat(raylib.GetTime() * 1e+9));
    //     // if (new_current_ns > current_ns) {
    //     //     current_ns = new_current_ns;
    //     // }
    //     // const delta_time = raylib.GetFrameTime();
    //     // current_ns += @max(@as(uint, @intFromFloat(delta_time * 1e+9)), 0);
    //     const last_object_processed_before = state.last_processed_object;
    //     state.process(timing_group, raylib.GetTime());
    //     const last_object_processed_after = state.last_processed_object;

    //     for (last_object_processed_before..last_object_processed_after) |i| {
    //         if (timing_group.objects[i].obj_type == rhythm.Conductor.ObjectType.Note) {
    //             const keysound_id = timing_group.notes[timing_group.objects[i].index].keysound_id - 1;
    //             const keysound = timing_group.keysounds[keysound_id];
    //             if (keysound != null) {
    //                 raylib.StopSound(keysound.?);
    //                 raylib.PlaySound(keysound.?);
    //             }
    //         }
    //     }

    //     const visual_beat = state.calculateVisualPosition(state.current_beat);

    //     std.debug.print("{d:.2} {d:.6}\n", .{ raylib.GetTime(), state.current_beat });

    //     raylib.ClearBackground(raylib.BLACK);

    //     raylib.DrawFPS(10, 10);

    //     var texts_drawn: u32 = 0;

    //     _ = try std.fmt.bufPrint(text1, "B\t{d:.3}\t{d:.3}\u{0000}", .{ state.current_beat, 60.0 / state.current_sec_per_beat });
    //     _ = try std.fmt.bufPrint(text2, "VB\t{d:.3}\u{0000}", .{visual_beat});

    //     raylib.DrawText(text1, 10, 20 + 20 * @as(i32, @intCast(texts_drawn)), 20, raylib.YELLOW);
    //     texts_drawn += 1;
    //     raylib.DrawText(text2, 10, 20 + 20 * @as(i32, @intCast(texts_drawn)), 20, raylib.YELLOW);
    //     texts_drawn += 1;

    //     const render_height = raylib.GetRenderHeight();

    //     for (timing_group.objects, positions, times, 0..) |object, position, time_sec, i| {
    //         _ = time_sec;
    //         // _ = try std.fmt.bufPrint(text1, "{s}{}\tT\t{d:.3}\tP\t{d:.3}\u{0000}", .{
    //         //     switch (object.obj_type) {
    //         //         rhythm.Conductor.ObjectType.Note => "Note",
    //         //         rhythm.Conductor.ObjectType.Segment => "Segment",
    //         //     },
    //         //     i,
    //         //     time_sec,
    //         //     position.visual_beat,
    //         // });

    //         var render_y = @as(i32, @intFromFloat((visual_beat - position.visual_beat) * scroll_speed_mul * c.beat_height));
    //         render_y += c.judgement_line_y;

    //         if (render_y < -c.note_height) {
    //             continue;
    //         }

    //         if (object.obj_type == rhythm.Conductor.ObjectType.Note) {
    //             const note = timing_group.notes[timing_group.objects[i].index];

    //             var render_x = @as(i32, note.lane);
    //             render_x *= c.note_width;

    //             // std.debug.print("{} {}\n", .{ time_sec, y });
    //             switch (note.type) {
    //                 rhythm.NoteTypeTag.normal => {
    //                     if (render_y > render_height + c.note_height) {
    //                         continue;
    //                     }
    //                     // raylib.DrawText(text1, render_x, render_y, 20, raylib.YELLOW);
    //                     raylib.DrawRectangle(
    //                         // Position
    //                         render_x,
    //                         render_y - c.note_height,
    //                         // Size
    //                         c.note_width,
    //                         c.note_height,
    //                         // Color
    //                         raylib.RED,
    //                     );
    //                 },
    //                 rhythm.NoteTypeTag.ln_head => {
    //                     var tail_render_y = @as(i32, @intFromFloat((visual_beat - positions[position.ln_tail_obj_index.?].visual_beat) * scroll_speed_mul * c.beat_height));
    //                     tail_render_y += c.judgement_line_y;
    //                     tail_render_y += c.note_height;
    //                     if (tail_render_y > render_height + c.note_height) {
    //                         continue;
    //                     }
    //                     // raylib.DrawText(text1, render_x, render_y, 20, raylib.YELLOW);
    //                     raylib.DrawRectangle(
    //                         // Position
    //                         render_x,
    //                         tail_render_y,
    //                         // Size
    //                         c.note_width,
    //                         render_y - tail_render_y,
    //                         // Color
    //                         raylib.RED,
    //                     );
    //                 },
    //                 else => {},
    //             }

    //             // texts_drawn += 1;
    //         } else if (object.obj_type == rhythm.Conductor.ObjectType.Segment) {
    //             if (render_y > render_height + c.note_height) {
    //                 continue;
    //             }
    //             const segment = timing_group.segments[timing_group.objects[i].index];
    //             switch (segment.type) {
    //                 rhythm.SegmentTypeTag.barline => {
    //                     raylib.DrawLine(0, render_y, c.note_width * 9, render_y, raylib.WHITE);
    //                 },
    //                 else => {
    //                     // raylib.DrawText(text1, 0, render_y, 20, raylib.YELLOW);
    //                 },
    //             }
    //         }
    //         // std.debug.print("{}\n", .{y});
    //     }

    //     raylib.DrawLine(0, c.judgement_line_y, c.note_width * 9, c.judgement_line_y, raylib.WHITE);
    // }
}
