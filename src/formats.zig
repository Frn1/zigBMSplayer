const std = @import("std");

const rhythm = @import("rhythm.zig");
const gfx = @import("graphics.zig");
const utils = @import("utils.zig");

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});
const ma = @cImport({
    @cDefine("MINIAUDIO_IMPLEMENTATION", {});
    @cInclude("miniaudio.h");
});

fn resetCurrentKeyValue(allocator: std.mem.Allocator, current_key: *[]u8, current_value: *[]u8) !void {
    allocator.free(current_key.*);
    allocator.free(current_value.*);

    current_key.* = try allocator.alloc(u8, 0);
    current_value.* = try allocator.alloc(u8, 0);
}

fn loadKeysound(arena_allocator: std.mem.Allocator, filename: []const u8, directory: std.fs.Dir, ma_engine: [*c]ma.ma_engine, output: *?*ma.ma_sound) !void {
    const filename_stem = std.fs.path.stem(filename);
    const filename_dirname = std.fs.path.dirname(filename);

    const filename_no_ext = if (filename_dirname == null)
        try arena_allocator.alloc(u8, filename_stem.len)
    else
        try std.fs.path.join(
            arena_allocator,
            &[_][]const u8{
                filename_dirname.?,
                filename_stem,
            },
        );
    defer arena_allocator.free(filename_no_ext);
    if (filename_dirname == null) {
        @memcpy(filename_no_ext, filename_stem);
    }

    const filename_ogg = try std.mem.join(arena_allocator, ".", &[_][]const u8{
        filename_no_ext,
        "ogg",
    });
    defer arena_allocator.free(filename_ogg);
    const filename_wav = try std.mem.join(arena_allocator, ".", &[_][]const u8{
        filename_no_ext,
        "wav",
    });
    defer arena_allocator.free(filename_wav);

    const directory_path = try directory.realpathAlloc(arena_allocator, ".");

    const flags = ma.MA_SOUND_FLAG_DECODE;

    if (directory.access(filename, std.fs.File.OpenFlags{})) {
        const path = try std.fs.path.joinZ(arena_allocator, &[_][]const u8{ directory_path, filename });
        defer arena_allocator.free(path);
        const result = ma.ma_sound_init_from_file(ma_engine, path, flags, null, null, output.*);
        if (result != ma.MA_SUCCESS) {
            return error.AudioLoadingError;
        }
    } else |err| switch (err) {
        error.FileNotFound => {
            if (directory.access(filename_ogg, std.fs.File.OpenFlags{})) {
                const path = try std.fs.path.joinZ(arena_allocator, &[_][]const u8{ directory_path, filename_ogg });
                defer arena_allocator.free(path);
                const result = ma.ma_sound_init_from_file(ma_engine, path, flags, null, null, output.*);
                if (result != ma.MA_SUCCESS) {
                    return error.AudioLoadingError;
                }
            } else |err2| switch (err2) {
                error.FileNotFound => {
                    if (directory.access(filename_wav, std.fs.File.OpenFlags{})) {
                        const path = try std.fs.path.joinZ(arena_allocator, &[_][]const u8{ directory_path, filename_wav });
                        defer arena_allocator.free(path);
                        const result = ma.ma_sound_init_from_file(ma_engine, path, flags, null, null, output.*);
                        if (result != ma.MA_SUCCESS) {
                            return error.AudioLoadingError;
                        }
                    } else |err3| switch (err3) {
                        error.FileNotFound => {
                            std.debug.print("Missing keysound {s}\n", .{filename_no_ext});
                        },
                        else => |leftover_err| return leftover_err,
                    }
                },
                else => |leftover_err| return leftover_err,
            }
        },
        else => |leftover_err| return leftover_err,
    }
}

pub fn compileBMS(allocator: std.mem.Allocator, ma_engine: [*c]ma.ma_engine, directory: []const u8, data: [:0]const u8) !rhythm.Conductor {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var arena_allocator = arena.allocator();

    var output = rhythm.Conductor{
        .notes = try allocator.alloc(rhythm.Note, 0),
        .segments = try allocator.alloc(rhythm.Segment, 0),
    };

    const Steps = enum { SkipUntilHashtag, ParseKey, ParseValue };
    var current_step = Steps.SkipUntilHashtag;

    var current_key = try arena_allocator.alloc(u8, 0);
    defer arena_allocator.free(current_key);

    var current_value = try arena_allocator.alloc(u8, 0);
    defer arena_allocator.free(current_value);

    var time_signatures = std.HashMap(u10, f64, struct {
        pub fn hash(self: @This(), key: u10) u64 {
            _ = self;
            return @intCast(key);
        }

        pub fn eql(self: @This(), a: u10, b: u10) bool {
            _ = self;
            return a == b;
        }
    }, 80).init(arena_allocator);

    const BmsObject = struct {
        measure: u10,
        fraction: f64,
        channel: u11,
        value: u11,

        pub fn lessThanFn(ctx: void, lhs: @This(), rhs: @This()) bool {
            _ = ctx;
            if (lhs.measure == rhs.measure) {
                if (lhs.fraction == rhs.fraction) {
                    return lhs.channel != 9 and rhs.channel == 9;
                }
                return lhs.fraction < rhs.fraction;
            }
            return lhs.measure < rhs.measure;
        }
    };
    var bms_objects = try arena_allocator.alloc(BmsObject, 0);
    defer arena_allocator.free(bms_objects);

    const RandomValue = struct {
        value: u32,
        skipping: bool = true,
        is_switch: bool = false,
        already_matched: bool = false,
    };
    const RandomStack = std.DoublyLinkedList(RandomValue);

    var random_stack = RandomStack{};
    defer for (0..random_stack.len) |_| {
        arena_allocator.destroy(random_stack.pop().?);
    };

    const BmsFloatDictionary = std.HashMap(u11, f64, struct {
        pub fn hash(self: @This(), key: u11) u64 {
            _ = self;
            return @intCast(key);
        }

        pub fn eql(self: @This(), a: u11, b: u11) bool {
            _ = self;
            return a == b;
        }
    }, 80);

    const BmsIntDictionary = std.HashMap(u11, u32, struct {
        pub fn hash(self: @This(), key: u11) u64 {
            _ = self;
            return @intCast(key);
        }

        pub fn eql(self: @This(), a: u11, b: u11) bool {
            _ = self;
            return a == b;
        }
    }, 80);

    const directory_realpath = try std.fs.cwd().realpathAlloc(allocator, directory);
    defer allocator.free(directory_realpath);
    const open_directory = try std.fs.openDirAbsolute(directory_realpath, std.fs.Dir.OpenDirOptions{});
    // var keysoundThreads: [1295]?std.Thread = .{null} ** 1295;

    var initial_bpm: f64 = 0.0;
    var bpm_values = BmsFloatDictionary.init(arena_allocator);
    var stop_values = BmsIntDictionary.init(arena_allocator);
    var scroll_values = BmsFloatDictionary.init(arena_allocator);

    var parsing_channel = false;

    for (data) |char| {
        switch (current_step) {
            Steps.SkipUntilHashtag => {
                if (char == '#') {
                    try resetCurrentKeyValue(arena_allocator, &current_key, &current_value);
                    current_step = Steps.ParseKey;
                    continue;
                }
            },
            Steps.ParseKey => {
                const maybe_skip = if (random_stack.len > 0) (random_stack.first.?.data.skipping) else false;

                if (char == ':') {
                    parsing_channel = true;
                    if (maybe_skip) {
                        current_step = Steps.SkipUntilHashtag;
                    } else {
                        current_step = Steps.ParseValue;
                    }
                    continue;
                } else if (std.ascii.isWhitespace(char) or std.ascii.isControl(char)) {
                    current_step = Steps.SkipUntilHashtag;

                    const is_skip = std.mem.eql(u8, current_key, "SKIP");
                    const is_else = std.mem.eql(u8, current_key, "ELSE");
                    const is_endif = std.mem.eql(u8, current_key, "ENDIF");
                    if (maybe_skip or is_skip or (maybe_skip == false and is_endif) or (maybe_skip == true and is_else)) {
                        const is_if = std.mem.eql(u8, current_key, "IF");
                        const is_case = std.mem.eql(u8, current_key, "CASE");
                        const is_def = std.mem.eql(u8, current_key, "DEF");
                        const is_endsw = std.mem.eql(u8, current_key, "ENDSW");
                        const is_endrandom = std.mem.eql(u8, current_key, "ENDRANDOM");

                        if (!is_if and !is_case and !is_else and !is_skip and !is_def and !is_endif and !is_endsw and !is_endrandom) {
                            continue;
                        }

                        const top_random_stack = random_stack.first.?;
                        if (top_random_stack.data.is_switch) {
                            if (is_skip and !top_random_stack.data.skipping and top_random_stack.data.already_matched) {
                                top_random_stack.*.data.skipping = true;
                            } else if (is_def and top_random_stack.data.skipping and !top_random_stack.data.already_matched) {
                                top_random_stack.*.data.skipping = false;
                            } else if (is_endsw) {
                                arena_allocator.destroy(random_stack.pop().?);
                            }
                        } else {
                            if (is_else) {
                                top_random_stack.*.data.skipping = !top_random_stack.data.skipping;
                            } else if (is_endif) {
                                top_random_stack.*.data.skipping = true;
                            } else if (is_endrandom) {
                                arena_allocator.destroy(random_stack.pop().?);
                            }
                        }
                    }

                    if (char == ' ') {
                        parsing_channel = false;
                        current_step = Steps.ParseValue;
                    } else {
                        current_step = Steps.SkipUntilHashtag;
                    }
                    continue;
                }
                current_key = try arena_allocator.realloc(current_key, current_key.len + 1);
                current_key[current_key.len - 1] = std.ascii.toUpper(char);
            },
            Steps.ParseValue => {
                if (char == '\r') { // Fuck you windows and your carrage returns 🖕
                    continue;
                } else if (char == '\n' or char == 0) {
                    current_step = Steps.SkipUntilHashtag;
                    const maybe_skip = if (random_stack.len > 0) (random_stack.first.?.data.skipping) else false;
                    if (parsing_channel) {
                        if (maybe_skip) {
                            continue;
                        }

                        const measure = try std.fmt.parseInt(u10, current_key[0..3], 10);
                        const channel = try std.fmt.parseInt(u11, current_key[3..5], 36);

                        switch (channel) {
                            2 => {
                                try time_signatures.put(measure, try std.fmt.parseFloat(f64, current_value));
                            },
                            else => {
                                const divisions = current_value.len / 2;
                                for (0..divisions) |i| {
                                    const number_base: u8 = if (channel == 3) 16 else 36;
                                    const value = try std.fmt.parseInt(u11, current_value[i * 2 .. i * 2 + 2], number_base);
                                    if (value == 0) {
                                        continue;
                                    }

                                    const fraction = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(divisions));

                                    bms_objects = try arena_allocator.realloc(bms_objects, bms_objects.len + 1);
                                    bms_objects[bms_objects.len - 1] = BmsObject{
                                        .measure = measure,
                                        .channel = channel,
                                        .fraction = fraction,
                                        .value = value,
                                    };
                                }
                            },
                        }
                    } else {
                        const is_random = std.mem.eql(u8, current_key, "RANDOM");
                        if ((maybe_skip == false and is_random) or maybe_skip) {
                            const is_if = std.mem.eql(u8, current_key, "IF");
                            const is_case = std.mem.eql(u8, current_key, "CASE");
                            const is_switch = std.mem.eql(u8, current_key, "SWITCH");

                            if (!is_if and !is_random and !is_case and !is_switch) {
                                continue;
                            }

                            if (is_switch) {
                                const new_node = try arena_allocator.create(RandomStack.Node);
                                new_node.* =
                                    RandomStack.Node{
                                    .prev = random_stack.last,
                                    .data = RandomValue{
                                        .value = std.Random.uintLessThan(
                                            std.crypto.random,
                                            u32,
                                            try std.fmt.parseInt(u32, current_value, 10),
                                        ) + 1,
                                        .is_switch = true,
                                    },
                                };
                                random_stack.append(new_node);
                            } else if (is_random) {
                                const new_node = try arena_allocator.create(RandomStack.Node);
                                new_node.* =
                                    RandomStack.Node{
                                    .prev = random_stack.last,
                                    .data = RandomValue{
                                        .value = std.Random.uintLessThan(
                                            std.crypto.random,
                                            u32,
                                            try std.fmt.parseInt(u32, current_value, 10),
                                        ) + 1,
                                    },
                                };
                                random_stack.append(new_node);
                            } else {
                                const top_random_stack = random_stack.first.?;
                                if (top_random_stack.data.is_switch) {
                                    if (is_case and top_random_stack.data.skipping and !top_random_stack.data.already_matched) {
                                        const value_to_match = try std.fmt.parseInt(u32, current_value, 10);
                                        if (top_random_stack.*.data.value == value_to_match) {
                                            top_random_stack.*.data.skipping = false;
                                            top_random_stack.*.data.already_matched = true;
                                        }
                                    }
                                } else if (is_if) {
                                    const value_to_match = try std.fmt.parseInt(u32, current_value, 10);
                                    if (top_random_stack.data.value == value_to_match and top_random_stack.data.already_matched == false) {
                                        top_random_stack.*.data.skipping = false;
                                        top_random_stack.*.data.already_matched = true;
                                    } else {
                                        top_random_stack.*.data.skipping = true;
                                    }
                                }
                            }
                        } else {
                            if (std.mem.eql(u8, current_key, "BPM")) {
                                initial_bpm = try std.fmt.parseFloat(f64, current_value);
                            } else if (std.mem.startsWith(u8, current_key, "BPM")) {
                                const key = try std.fmt.parseInt(u11, current_key[3..5], 36);
                                const bpm = try std.fmt.parseFloat(f64, current_value);
                                try bpm_values.put(key, bpm);
                            } else if (std.mem.startsWith(u8, current_key, "STOP")) {
                                const key = try std.fmt.parseInt(u11, current_key[4..6], 36);
                                const stopped_time = try std.fmt.parseInt(u32, current_value, 10); // 1 unit corresponds 1/192 of measure with 4/4 meter
                                try stop_values.put(key, stopped_time);
                            } else if (std.mem.startsWith(u8, current_key, "SCROLL")) {
                                const key = try std.fmt.parseInt(u11, current_key[6..8], 36);
                                const new_scroll = try std.fmt.parseFloat(f64, current_value);
                                try scroll_values.put(key, new_scroll);
                            } else if (std.mem.startsWith(u8, current_key, "WAV")) {
                                const index = try std.fmt.parseInt(u11, current_key[3..5], 36) - 1;

                                const filenameCopy = try arena_allocator.alloc(u8, current_value.len);
                                defer arena_allocator.free(filenameCopy);
                                @memcpy(filenameCopy, current_value);

                                if (output.keysounds[index] != null) {
                                    // if there is a sound already loaded in that place, unload it so we dont cause a memory leak
                                    allocator.destroy(output.keysounds[index].?);
                                    ma.ma_sound_uninit(output.keysounds[index].?);
                                    output.keysounds[index] = null;
                                }

                                output.keysounds[index] = try allocator.create(ma.ma_sound);

                                loadKeysound(
                                    arena_allocator,
                                    filenameCopy,
                                    open_directory,
                                    ma_engine,
                                    &output.keysounds[index],
                                ) catch |e| {
                                    utils.showError(
                                        "Couldn't load keysound",
                                        try std.fmt.allocPrintZ(
                                            arena_allocator,
                                            "Keysound with id {d} at path {s} failed to load\n{!}",
                                            .{ index, filenameCopy, e },
                                        ),
                                    );
                                };
                            }
                        }
                    }
                    continue;
                }
                current_value = try arena_allocator.realloc(current_value, current_value.len + 1);
                current_value[current_value.len - 1] = char;
            },
        }
    }

    std.sort.heap(BmsObject, bms_objects, {}, BmsObject.lessThanFn);

    // Add initial bpm change
    output.segments = try allocator.realloc(output.segments, output.segments.len + 2);
    output.segments[output.segments.len - 2] = rhythm.Segment{
        .beat = 0,
        .type = rhythm.SegmentType{ .bpm = initial_bpm },
    };
    output.segments[output.segments.len - 1] = rhythm.Segment{
        .beat = 0,
        .type = rhythm.SegmentType{ .scroll = 1 },
    };

    const ActiveLnLanesType = std.DoublyLinkedList(struct { lane: u4, note_index: usize });
    var active_ln_lanes = ActiveLnLanesType{};
    var last_processed_measure: u10 = 0;
    var beats_until_now: f80 = 0.0;
    var beats_in_measure: f80 = 4.0;
    for (bms_objects) |object| {
        if (last_processed_measure != object.measure) {
            for (last_processed_measure..object.measure) |measure_usize| {
                const measure: u10 = @intCast(measure_usize);
                const beats_in_measure_multiplier: ?f64 = time_signatures.get(@intCast(measure));
                if (beats_in_measure_multiplier == null) {
                    beats_in_measure = 4.0;
                } else {
                    beats_in_measure = 4.0 * @as(f80, @floatCast(beats_in_measure_multiplier.?));
                }
                beats_until_now += beats_in_measure;
                output.segments = try allocator.realloc(output.segments, output.segments.len + 1);
                output.segments[output.segments.len - 1] = rhythm.Segment{
                    .beat = beats_until_now,
                    .type = rhythm.SegmentType{ .barline = {} },
                };
                last_processed_measure = measure;
            }
            const beats_in_measure_multiplier: ?f64 = time_signatures.get(@intCast(object.measure));
            if (beats_in_measure_multiplier == null) {
                beats_in_measure = 4.0;
            } else {
                beats_in_measure = 4.0 * @as(f80, @floatCast(beats_in_measure_multiplier.?));
            }
            last_processed_measure = object.measure;
        }

        const beat = beats_until_now + object.fraction * beats_in_measure;

        switch (object.channel) {
            3 => {
                output.segments = try allocator.realloc(output.segments, output.segments.len + 1);
                output.segments[output.segments.len - 1] = rhythm.Segment{
                    .beat = beat,
                    .type = rhythm.SegmentType{
                        .bpm = @floatFromInt(object.value),
                    },
                };
            },
            8 => {
                output.segments = try allocator.realloc(output.segments, output.segments.len + 1);
                output.segments[output.segments.len - 1] = rhythm.Segment{
                    .beat = beat,
                    .type = rhythm.SegmentType{
                        .bpm = bpm_values.get(object.value).?,
                    },
                };
            },
            9 => {
                const duration_beats = 4 * @as(f80, @floatFromInt(stop_values.get(object.value).?)) / 192.0;
                // std.debug.print("{} {any}\n", .{ object.value, duration_beats });

                output.segments = try allocator.realloc(output.segments, output.segments.len + 1);
                output.segments[output.segments.len - 1] = rhythm.Segment{
                    .beat = beat,
                    .type = rhythm.SegmentType{
                        .stop = duration_beats,
                    },
                };
            },
            1020 => { // Channel SC
                const new_scroll = scroll_values.get(object.value).?;
                output.segments = try allocator.realloc(output.segments, output.segments.len + 1);
                output.segments[output.segments.len - 1] = rhythm.Segment{
                    .beat = beat,
                    .type = rhythm.SegmentType{
                        .scroll = new_scroll,
                    },
                };
            },
            1 => {
                output.notes = try allocator.realloc(output.notes, output.notes.len + 1);
                output.notes[output.notes.len - 1].beat = beat;
                output.notes[output.notes.len - 1].lane = 0;
                output.notes[output.notes.len - 1].type = rhythm.NoteType{ .bgm = {} };
                output.notes[output.notes.len - 1].keysound_id = object.value;
            },
            37...46 => {
                output.notes = try allocator.realloc(output.notes, output.notes.len + 1);
                output.notes[output.notes.len - 1].beat = beat;
                output.notes[output.notes.len - 1].lane = @intCast(object.channel - 37);
                output.notes[output.notes.len - 1].type = rhythm.NoteType{
                    .normal = rhythm.NormalNoteType.normal,
                };
                output.notes[output.notes.len - 1].keysound_id = object.value;
            },
            73...82 => {
                output.notes = try allocator.realloc(output.notes, output.notes.len + 1);
                output.notes[output.notes.len - 1].beat = beat;
                output.notes[output.notes.len - 1].lane = @intCast(object.channel - 73);
                output.notes[output.notes.len - 1].lane += 9;
                output.notes[output.notes.len - 1].type = rhythm.NoteType{
                    .normal = rhythm.NormalNoteType.normal,
                };
                output.notes[output.notes.len - 1].keysound_id = object.value;
            },
            109...118 => {
                output.notes = try allocator.realloc(output.notes, output.notes.len + 1);
                output.notes[output.notes.len - 1].beat = beat;
                output.notes[output.notes.len - 1].lane = @intCast(object.channel - 109);
                output.notes[output.notes.len - 1].type = rhythm.NoteType{
                    .normal = rhythm.NormalNoteType.hidden,
                };
                output.notes[output.notes.len - 1].keysound_id = object.value;
            },
            145...154 => {
                output.notes = try allocator.realloc(output.notes, output.notes.len + 1);
                output.notes[output.notes.len - 1].beat = beat;
                output.notes[output.notes.len - 1].lane = @intCast(object.channel - 145);
                output.notes[output.notes.len - 1].lane += 9;
                output.notes[output.notes.len - 1].type = rhythm.NoteType{
                    .normal = rhythm.NormalNoteType.hidden,
                };
                output.notes[output.notes.len - 1].keysound_id = object.value;
            },
            181...190 => {
                output.notes = try allocator.realloc(output.notes, output.notes.len + 1);
                output.notes[output.notes.len - 1].beat = beat;
                output.notes[output.notes.len - 1].lane = @intCast(object.channel - 181);
                var node = active_ln_lanes.first;
                for (0..active_ln_lanes.len) |_| {
                    if (output.notes[output.notes.len - 1].lane == node.?.data.lane) {
                        if (output.notes[node.?.data.note_index].keysound_id == object.value) {
                            output.notes[node.?.data.note_index].type = rhythm.NoteType{
                                .ln_head = output.notes.len - 1,
                            };
                            active_ln_lanes.remove(node.?);
                            break;
                        }
                    }
                    node = node.?.next;
                } else {
                    output.notes[output.notes.len - 1].type = rhythm.NoteType{
                        .ln_head = 0,
                    };
                    const new_node = try arena_allocator.create(ActiveLnLanesType.Node);
                    new_node.prev = active_ln_lanes.last;
                    new_node.data = .{
                        .lane = output.notes[output.notes.len - 1].lane,
                        .note_index = output.notes.len - 1,
                    };
                    active_ln_lanes.append(new_node);
                }
                output.notes[output.notes.len - 1].type = rhythm.NoteType{
                    .ln_tail = rhythm.LongNoteType.normal,
                };
                output.notes[output.notes.len - 1].keysound_id = object.value;
            },
            217...226 => {
                output.notes = try allocator.realloc(output.notes, output.notes.len + 1);
                output.notes[output.notes.len - 1].beat = beat;
                output.notes[output.notes.len - 1].lane = @intCast(object.channel - 217);
                output.notes[output.notes.len - 1].lane += 9;
                var node = active_ln_lanes.first;
                for (0..active_ln_lanes.len) |_| {
                    if (output.notes[output.notes.len - 1].lane == node.?.data.lane) {
                        if (output.notes[node.?.data.note_index].keysound_id == object.value) {
                            output.notes[node.?.data.note_index].type = rhythm.NoteType{
                                .ln_head = output.notes.len - 1,
                            };
                            active_ln_lanes.remove(node.?);
                            break;
                        }
                    }
                    node = node.?.next;
                } else {
                    output.notes[output.notes.len - 1].type = rhythm.NoteType{
                        .ln_head = 0,
                    };
                    const new_node = try allocator.create(ActiveLnLanesType.Node);
                    new_node.prev = active_ln_lanes.last;
                    new_node.data = .{
                        .lane = output.notes[output.notes.len - 1].lane,
                        .note_index = output.notes.len - 1,
                    };
                    active_ln_lanes.append(new_node);
                }
                output.notes[output.notes.len - 1].type = rhythm.NoteType{
                    .ln_tail = rhythm.LongNoteType.normal,
                };
                output.notes[output.notes.len - 1].keysound_id = object.value;
            },
            else => {},
        }
    }

    output.sortNotes();
    output.sortSegments();

    // for (keysoundThreads) |thread| {
    //     if (thread == null) continue;

    //     thread.?.join();
    // }

    return output;
}
