const std = @import("std");

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

const Conductor = @import("rhythm/conductor.zig").Conductor;
const Object = @import("rhythm/object.zig").Object;
const ScrollObject = @import("rhythm/objects/scroll.zig");
const StopObject = @import("rhythm/objects/stop.zig");
const BPMObject = @import("rhythm/objects/bpm.zig");
const BGMObject = @import("rhythm/objects/bgm.zig");
const NoteObject = @import("rhythm/objects/note.zig");
const LNHeadObject = @import("rhythm/objects/ln_head.zig");
const LNTailObject = @import("rhythm/objects/ln_tail.zig");
const BarlineObject = @import("rhythm/objects/barline.zig");
const Lane = @import("rhythm/objects/note.zig").Lane;

const BMSMeasure = u10;
const BMSChannel = u11;
const BMSValue = u11;
const RandomNumber = u32;
const KeysoundId = BMSValue;

fn resetCurrentKeyValue(allocator: std.mem.Allocator, current_key: *[]u8, current_value: *[]u8) !void {
    allocator.free(current_key.*);
    allocator.free(current_value.*);

    current_key.* = try allocator.alloc(u8, 0);
    current_value.* = try allocator.alloc(u8, 0);
}

fn channelToLane(channel: BMSChannel) !NoteObject.Lane {
    return switch (channel) {
        0 => Lane.White1_P1,
        1 => Lane.Black1_P1,
        2 => Lane.White2_P1,
        3 => Lane.Black2_P1,
        4 => Lane.White3_P1,
        5 => Lane.Scratch_P1,
        7 => Lane.Black3_P1,
        8 => Lane.White4_P1,
        36 => Lane.White1_P2,
        37 => Lane.Black1_P2,
        38 => Lane.White2_P2,
        39 => Lane.Black2_P2,
        40 => Lane.White3_P2,
        41 => Lane.Scratch_P2,
        43 => Lane.Black3_P2,
        44 => Lane.White4_P2,
        else => return error.UnknownGameMode, // The channel isnt in here, so it's probably something else
    };
}

fn addBGM(allocator: std.mem.Allocator, conductor: *Conductor, beat: Object.Time, keysound_id: KeysoundId) !void {
    conductor.objects = try allocator.realloc(conductor.objects, conductor.objects.len + 1);
    conductor.objects[conductor.objects.len - 1] = try BGMObject.create(
        allocator,
        beat,
        conductor.keysounds[keysound_id],
    );
}

fn addNote(allocator: std.mem.Allocator, conductor: *Conductor, beat: Object.Time, lane: Lane, keysound_id: KeysoundId) !void {
    conductor.objects = try allocator.realloc(conductor.objects, conductor.objects.len + 1);
    conductor.objects[conductor.objects.len - 1] = try NoteObject.create(
        allocator,
        beat,
        lane,
        conductor.keysounds[keysound_id],
    );
}

fn addLNHead(allocator: std.mem.Allocator, conductor: *Conductor, beat: Object.Time, lane: Lane, keysound_id: KeysoundId) !void {
    conductor.objects = try allocator.realloc(conductor.objects, conductor.objects.len + 1);
    conductor.objects[conductor.objects.len - 1] = try LNHeadObject.create(
        allocator,
        beat,
        lane,
        conductor.keysounds[keysound_id],
    );
}

fn addLNTail(allocator: std.mem.Allocator, conductor: *Conductor, beat: Object.Time) !void {
    conductor.objects = try allocator.realloc(conductor.objects, conductor.objects.len + 1);
    conductor.objects[conductor.objects.len - 1] = LNTailObject.create(beat);
}

fn addBPM(allocator: std.mem.Allocator, conductor: *Conductor, beat: Object.Time, bpm: Object.Time) !void {
    conductor.objects = try allocator.realloc(conductor.objects, conductor.objects.len + 1);
    conductor.objects[conductor.objects.len - 1] = try BPMObject.create(
        allocator,
        beat,
        bpm,
    );
}

fn addScroll(allocator: std.mem.Allocator, conductor: *Conductor, beat: Object.Time, scroll: Object.Position) !void {
    conductor.objects = try allocator.realloc(conductor.objects, conductor.objects.len + 1);
    conductor.objects[conductor.objects.len - 1] = try ScrollObject.create(
        allocator,
        beat,
        scroll,
    );
}

fn addStop(allocator: std.mem.Allocator, conductor: *Conductor, beat: Object.Time, duration: Object.Time) !void {
    conductor.objects = try allocator.realloc(conductor.objects, conductor.objects.len + 1);
    conductor.objects[conductor.objects.len - 1] = try StopObject.create(
        allocator,
        beat,
        duration,
    );
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

pub fn compileBMS(allocator: std.mem.Allocator, ma_engine: [*c]ma.ma_engine, directory: []const u8, data: [:0]const u8) !Conductor {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var arena_allocator = arena.allocator();

    var output = Conductor{
        .objects = try allocator.alloc(Object, 1),
    };

    const Steps = enum { SkipUntilHashtag, ParseKey, ParseValue };
    var current_step = Steps.SkipUntilHashtag;

    var current_key = try arena_allocator.alloc(u8, 0);
    defer arena_allocator.free(current_key);

    var current_value = try arena_allocator.alloc(u8, 0);
    defer arena_allocator.free(current_value);

    var time_signatures = std.HashMap(BMSMeasure, f64, struct {
        pub fn hash(self: @This(), key: BMSMeasure) u64 {
            _ = self;
            return @intCast(key);
        }

        pub fn eql(self: @This(), a: BMSMeasure, b: BMSMeasure) bool {
            _ = self;
            return a == b;
        }
    }, 80).init(arena_allocator);

    const BmsObject = struct {
        measure: BMSMeasure,
        fraction: f64,
        channel: BMSChannel,
        value: BMSValue,

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
        number: RandomNumber,
        skipping: bool = true,
        is_switch: bool = false,
        already_matched: bool = false,
    };
    const RandomStack = std.DoublyLinkedList(RandomValue);

    var random_stack = RandomStack{};
    defer for (0..random_stack.len) |_| {
        arena_allocator.destroy(random_stack.pop().?);
    };

    const VauleTimeHashMap = std.HashMap(BMSValue, Object.Time, struct {
        pub fn hash(self: @This(), key: BMSValue) u64 {
            _ = self;
            return @intCast(key);
        }

        pub fn eql(self: @This(), a: BMSValue, b: BMSValue) bool {
            _ = self;
            return a == b;
        }
    }, 80);

    const VaulePositionHashMap = std.HashMap(BMSValue, Object.Position, struct {
        pub fn hash(self: @This(), key: BMSValue) u64 {
            _ = self;
            return @intCast(key);
        }

        pub fn eql(self: @This(), a: BMSValue, b: BMSValue) bool {
            _ = self;
            return a == b;
        }
    }, 80);

    const directory_realpath = try std.fs.cwd().realpathAlloc(allocator, directory);
    defer allocator.free(directory_realpath);
    const open_directory = try std.fs.openDirAbsolute(directory_realpath, std.fs.Dir.OpenDirOptions{});
    // var keysoundThreads: [1295]?std.Thread = .{null} ** 1295;

    var ln_obj: ?BMSValue = null;
    var initial_bpm: Object.Time = 0.0;
    var bpm_values = VauleTimeHashMap.init(arena_allocator);
    var stop_values = VauleTimeHashMap.init(arena_allocator);
    var scroll_values = VaulePositionHashMap.init(arena_allocator);

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
                                top_random_stack.data.skipping = true;
                            } else if (is_def and top_random_stack.data.skipping and !top_random_stack.data.already_matched) {
                                top_random_stack.data.skipping = false;
                            } else if (is_endsw) {
                                arena_allocator.destroy(random_stack.pop().?);
                            }
                        } else {
                            if (is_else) {
                                top_random_stack.data.skipping = !top_random_stack.data.skipping;
                            } else if (is_endif) {
                                top_random_stack.data.skipping = true;
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

                        const measure = try std.fmt.parseInt(BMSMeasure, current_key[0..3], 10);
                        const channel = try std.fmt.parseInt(BMSChannel, current_key[3..5], 36);

                        switch (channel) {
                            2 => {
                                try time_signatures.put(measure, try std.fmt.parseFloat(f64, current_value));
                            },
                            else => {
                                const divisions = current_value.len / 2;
                                for (0..divisions) |i| {
                                    const number_base: u8 = if (channel == 3) 16 else 36;
                                    const value = try std.fmt.parseInt(BMSValue, current_value[i * 2 .. i * 2 + 2], number_base);
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
                                        .number = std.Random.uintLessThan(
                                            std.crypto.random,
                                            RandomNumber,
                                            try std.fmt.parseInt(RandomNumber, current_value, 10),
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
                                        .number = std.Random.uintLessThan(
                                            std.crypto.random,
                                            RandomNumber,
                                            try std.fmt.parseInt(RandomNumber, current_value, 10),
                                        ) + 1,
                                    },
                                };
                                random_stack.append(new_node);
                            } else {
                                const top_random_stack = random_stack.first.?;
                                if (top_random_stack.data.is_switch) {
                                    if (is_case and top_random_stack.data.skipping and !top_random_stack.data.already_matched) {
                                        const value_to_match = try std.fmt.parseInt(RandomNumber, current_value, 10);
                                        if (top_random_stack.data.number == value_to_match) {
                                            top_random_stack.data.skipping = false;
                                            top_random_stack.data.already_matched = true;
                                        }
                                    }
                                } else if (is_if) {
                                    const value_to_match = try std.fmt.parseInt(RandomNumber, current_value, 10);
                                    if (top_random_stack.data.number == value_to_match and top_random_stack.data.already_matched == false) {
                                        top_random_stack.data.skipping = false;
                                        top_random_stack.data.already_matched = true;
                                    } else {
                                        top_random_stack.data.skipping = true;
                                    }
                                }
                            }
                        } else {
                            if (std.mem.eql(u8, current_key, "BPM")) {
                                initial_bpm = try std.fmt.parseFloat(f64, current_value);
                            } else if (std.mem.startsWith(u8, current_key, "BPM")) {
                                const key = try std.fmt.parseInt(BMSValue, current_key[3..5], 36);
                                const bpm = try std.fmt.parseFloat(f64, current_value);
                                try bpm_values.put(key, bpm);
                            } else if (std.mem.startsWith(u8, current_key, "STOP")) {
                                const key = try std.fmt.parseInt(BMSValue, current_key[4..6], 36);
                                const stopped_time: Object.Time = 4 * @as(
                                    Object.Time,
                                    @floatFromInt(
                                        try std.fmt.parseInt(RandomNumber, current_value, 10),
                                    ),
                                ) / 192.0; // 1 unit corresponds 1/192 of measure with 4/4 meter
                                try stop_values.put(key, stopped_time);
                            } else if (std.mem.startsWith(u8, current_key, "SCROLL")) {
                                const key = try std.fmt.parseInt(BMSValue, current_key[6..8], 36);
                                const new_scroll = try std.fmt.parseFloat(f32, current_value);
                                try scroll_values.put(key, new_scroll);
                            } else 
                            if (std.mem.eql(u8, current_key, "LNOBJ")) {
                                ln_obj = try std.fmt.parseInt(BMSValue, current_value, 36) - 1;
                            } else if (std.mem.startsWith(u8, current_key, "WAV")) {
                                const index = try std.fmt.parseInt(BMSValue, current_key[3..5], 36) - 1;

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
    output.objects[0] = try BPMObject.create(allocator, 0, initial_bpm);

    const ActiveLnLanesType = std.DoublyLinkedList(struct { lane: NoteObject.Lane, note_index: usize });
    var active_ln_lanes = ActiveLnLanesType{};
    var last_processed_measure: BMSMeasure = 0;
    var beats_until_now: f80 = 0.0;
    var beats_in_measure: f80 = 4.0;
    var is_doubles = false;
    var uses_7_lanes = false;
    var last_note_index_for_lane: [Lane.number_of_lanes]?usize = .{null} ** Lane.number_of_lanes; 
    for (bms_objects) |object| {
        if (last_processed_measure != object.measure) {
            for (last_processed_measure..object.measure) |measure_usize| {
                const measure: BMSMeasure = @intCast(measure_usize);
                const beats_in_measure_multiplier: ?f64 = time_signatures.get(@intCast(measure));
                if (beats_in_measure_multiplier == null) {
                    beats_in_measure = 4.0;
                } else {
                    beats_in_measure = 4.0 * @as(f80, @floatCast(beats_in_measure_multiplier.?));
                }
                beats_until_now += beats_in_measure;
                output.objects = try allocator.realloc(output.objects, output.objects.len + 1);
                output.objects[output.objects.len - 1] = try BarlineObject.create(
                    allocator,
                    beats_until_now,
                );
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
            3 => try addBPM(
                allocator,
                &output,
                beat,
                @floatFromInt(object.value),
            ),
            8 => try addBPM(
                allocator,
                &output,
                beat,
                bpm_values.get(object.value).?,
            ),
            9 => try addStop(
                allocator,
                &output,
                beat,
                stop_values.get(object.value).?,
            ),
            1020 => try addScroll(
                allocator,
                &output,
                beat,
                scroll_values.get(object.value).?,
            ),
            1 => try addBGM(
                allocator,
                &output,
                beat,
                object.value - 1,
            ),
            37...108 => {
                const lane = try channelToLane(object.channel - 37);
                
                switch (lane) {
                    .Black3_P1, .White4_P1 => {
                        uses_7_lanes = true;
                    },
                    .White1_P2, .Black1_P2, .White2_P2, .Black2_P2, .White3_P2, .Scratch_P2 => {
                        is_doubles = true;
                    },
                    .Black3_P2, .White4_P2 => {
                        uses_7_lanes = true;
                        is_doubles = true;
                    },
                    else => {},
                }
                
                const last_note_index_in_lane = last_note_index_for_lane[@intFromEnum(lane)];
                defer last_note_index_for_lane[@intFromEnum(lane)] = output.objects.len;
                if (last_note_index_in_lane != null and ln_obj != null) {
                    const last_index_in_lane = last_note_index_in_lane.?;
                    const last_note_in_lane = output.objects[last_index_in_lane];
                    const parameters = Object.castParameters(NoteObject.Parameters, last_note_in_lane.parameters);
                    if (parameters.sound == output.keysounds[ln_obj.?]) {
                        // TODO: Convert note to LN Head
                        // TODO: Add LN Tail
                        continue; // Stop the code from adding a normal note
                    }
                }

                try addNote(
                    allocator,
                    &output,
                    beat,
                    lane,
                    object.value - 1,
                );
            },
            //     109...144 => {
            //         output.notes = try allocator.realloc(output.notes, output.notes.len + 1);
            //         output.notes[output.notes.len - 1].beat = beat;
            //         const lane = object.channel - 109;
            //         output.notes[output.notes.len - 1].lane = @intCast(switch (lane) {
            //             0...4 => lane + 1,
            //             5 => 0,
            //             else => lane - 1,
            //         });
            //         if (lane >= 6 and lane <= 8 and output.chart_type == .beat5k) {
            //             output.chart_type = .beat7k;
            //         } else if (lane >= 6 and lane <= 8 and output.chart_type == .beat10k) {
            //             output.chart_type = .beat14k;
            //         }
            //         if (lane > 8) {
            //             // This is probably pomu, which is unsupported for now
            //             return error.UnsuportedMode;
            //         }
            //         output.notes[output.notes.len - 1].type = rhythm.NoteType{
            //             .normal = rhythm.NormalNoteType.hidden,
            //         };
            //         output.notes[output.notes.len - 1].keysound_id = object.value;
            //     },
            //     145...180 => {
            //         output.notes = try allocator.realloc(output.notes, output.notes.len + 1);
            //         output.notes[output.notes.len - 1].beat = beat;
            //         const lane = object.channel - 145;
            //         output.notes[output.notes.len - 1].lane = @intCast(switch (lane) {
            //             0...4 => lane + 1,
            //             5 => 0,
            //             else => lane - 1,
            //         });
            //         if (output.chart_type == .beat5k) {
            //             output.chart_type = .beat10k;
            //         }
            //         if (lane >= 6 and lane <= 8 and (output.chart_type == .beat5k or output.chart_type == .beat10k)) {
            //             output.chart_type = .beat14k;
            //         }
            //         if (lane > 8) {
            //             // This is probably pomu, which is unsupported for now
            //             return error.UnsuportedMode;
            //         }
            //         output.notes[output.notes.len - 1].lane += 36;
            //         output.notes[output.notes.len - 1].type = rhythm.NoteType{
            //             .normal = rhythm.NormalNoteType.hidden,
            //         };
            //         output.notes[output.notes.len - 1].keysound_id = object.value;
            //     },
            181...251 => {
                const lane = try channelToLane(object.channel - 181);
                switch (lane) {
                    .Black3_P1, .White4_P1 => {
                        uses_7_lanes = true;
                    },
                    .White1_P2, .Black1_P2, .White2_P2, .Black2_P2, .White3_P2, .Scratch_P2 => {
                        is_doubles = true;
                    },
                    .Black3_P2, .White4_P2 => {
                        uses_7_lanes = true;
                        is_doubles = true;
                    },
                    else => {},
                }

                var node = active_ln_lanes.first;
                for (0..active_ln_lanes.len) |_| {
                    if (lane == node.?.data.lane) {
                        const ln_head_parameters = Object.castParameters(LNHeadObject.Parameters, output.objects[node.?.data.note_index].parameters);
                        if (output.keysounds[object.value] == ln_head_parameters.sound) {
                            try addLNTail(allocator, &output, beat);
                            ln_head_parameters.tail_obj_index = output.objects.len - 1;
                            active_ln_lanes.remove(node.?);
                            break;
                        }
                    }
                    node = node.?.next;
                } else {
                    try addLNHead(allocator, &output, beat, lane, object.value);
                    const new_node = try arena_allocator.create(ActiveLnLanesType.Node);
                    new_node.prev = active_ln_lanes.last;
                    new_node.data = .{
                        .lane = lane,
                        .note_index = output.objects.len - 1,
                    };
                    active_ln_lanes.append(new_node);
                }
            },
            else => {},
        }
    }

    // output.sortNotes();
    // output.sortSegments();

    // for (keysoundThreads) |thread| {
    //     if (thread == null) continue;

    //     thread.?.join();
    // }

    if (uses_7_lanes) {
        output.chart_type = if (is_doubles) .beat14k else .beat7k;
    } else {
        output.chart_type = if (is_doubles) .beat10k else .beat5k;
    }
    return output;
}
