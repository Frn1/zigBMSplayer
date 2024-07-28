const std = @import("std");

const Object = @import("object.zig").Object;

const ma_sound = @cImport({
    @cDefine("MINIAUDIO_IMPLEMENTATION", {});
    @cInclude("miniaudio.h");
}).ma_sound;

pub const ChartType = enum { beat7k, beat5k, beat14k, beat10k };

pub const Conductor = struct {
    chart_type: ChartType = .beat5k,
    objects: []Object,
    keysounds: [1295]?*ma_sound = .{null} ** 1295,

    pub fn sortObjects(self: Conductor) void {
        std.sort.heap(
            Object,
            self.objects,
            self,
            Object.lessThanFn,
        );
    }

    pub fn destroyObjects(self: *Conductor, allocator: std.mem.Allocator) void {
        for (self.objects) |object| {
            object.destroy(object, allocator);
        }
        allocator.free(self.objects);
    }

    /// Calculate seconds and positions for each object in this conductor
    ///
    /// The arguments (except for self) are optional.
    pub fn calculateSecondsAndPositions(
        self: @This(),
        output_seconds: ?[]Object.Time,
        output_positions: ?[]Object.Position,
    ) error{OutputTooSmall}!void {
        if (output_seconds != null and self.objects.len > output_seconds.?.len) {
            return error.OutputTooSmall;
        } else if (output_positions != null and self.objects.len > output_positions.?.len) {
            return error.OutputTooSmall;
        }

        var state = State{};

        for (self.objects, 0..self.objects.len) |object, index| {
            const time = state.convertBeatToSeconds(object.beat);
            if (output_seconds != null) {
                output_seconds.?[index] = time;
            }
            state.update(self, time, false);
            const position = state.calculateVisualPosition(object.beat);
            if (output_positions != null) {
                output_positions.?[index] = position;
            }
        }
    }

    /// `calculateSecondsAndPositions` but using the allocator to automatically create the output.
    ///
    /// **The caller is required to handle freeing the memory created.**
    pub fn calculateSecondsAndPositionsAlloc(
        self: @This(),
        allocator: std.mem.Allocator,
    ) error{OutputTooSmall}!struct {
        seconds: []Object.Time,
        positions: []Object.Position,
    } {
        const output_seconds = try allocator.alloc(Object.Time, self.objects.len);
        const output_positions = try allocator.alloc(Object.Position, self.objects.len);

        // Since we allocated the outputs to be the size of the objects,
        // this can't fail for that reason
        try self.calculateSecondsAndPositions(output_seconds, output_positions) catch |err| switch (err) {
            error.OutputTooSmall => undefined,
            else => return err,
        };

        return .{ .seconds = output_seconds, .positions = output_positions };
    }

    /// Calculate only the seconds for each object in this conductor
    pub fn calculateSeconds(self: @This(), output: []Object.Time) !void {
        return try self.calculateSecondsAndPositions(output, null);
    }

    /// `calculateSeconds` but using the allocator to automatically create the output.
    ///
    /// **The caller is required to handle freeing the memory created.**
    pub fn calculateSecondsAlloc(self: @This(), allocator: std.mem.Allocator) ![]f80 {
        const output = try allocator.alloc(Object.Time, self.objects.len);

        // Since we allocated the output to be the size of the objects,
        // this can't fail for that reason
        self.calculateSeconds(output) catch |err| switch (err) {
            error.OutputTooSmall => undefined,
            else => return err,
        };

        return output;
    }

    /// Calculate only the position for each object in this conductor
    pub fn calculatePositions(self: @This(), output: []Object.Position) !void {
        return try self.calculateSecondsAndPositions(null, output);
    }

    pub fn calculatePositionsAlloc(self: @This(), allocator: std.mem.Allocator) ![]Object.Position {
        const output = try allocator.alloc(Object.Position, self.objects.len);

        // Since we allocated the output to be the size of the objects,
        // this can't fail for that reason
        self.calculatePositions(output) catch |err| switch (err) {
            error.OutputTooSmall => undefined,
            else => return err,
        };

        return output;
    }

    pub const State = struct {
        /// The next object to process
        next_object_to_process: usize = 0,

        /// Current seconds per beat.
        /// (`60/BPM`)
        ///
        /// Should always be positive and NEVER 0 or lower.
        /// (Unless the state is at its default un-processed state)
        seconds_per_beat: Object.Time = std.math.inf(f80),
        /// Seconds to subtruct from the `current_time` when calculating `current_beat`.
        seconds_offset: Object.Time = 0,
        /// Beats to add when calculating current_beat.
        beats_offset: Object.Time = 0,

        /// Beats to subtract when calculating visual position.
        visual_beats_offset: Object.Position = 0,
        /// Offset to add when calculating visual position.
        visual_pos_offset: Object.Position = 0,
        /// Current scroll multiplier.
        /// Used for calculating the current visual position.
        scroll_mul: Object.Position = 1.0,

        /// The current beat.
        /// It should **always** go higher or stop and **NEVER** go back in time.
        /// (Unless the state is reset)
        beat: Object.Time = 0,

        /// Recalculates the current beat.
        ///
        /// **(It can only guarantee accuracy from the last object until the next object)**
        inline fn updateBeat(self: *@This(), current_sec: Object.Time) void {
            self.beat = self.convertSecondsToBeats(current_sec);
        }

        /// Calculate the visual position at `beat`.
        ///
        /// **(It can only guarantee accuracy from the last object until the next object)**
        pub inline fn calculateVisualPosition(self: @This(), beat: Object.Time) Object.Position {
            return @as(Object.Position, @floatCast(
                beat - @as(Object.Time, @floatCast(self.visual_beats_offset)),
            )) * self.scroll_mul + self.visual_pos_offset;
        }

        /// Convert `beats` into seconds
        ///
        /// Inverse operation of `convertSecondsToBeats`.
        ///
        /// **(It can only guarantee accuracy from the last object until the next object)**
        pub inline fn convertBeatToSeconds(self: @This(), beats: f80) f80 {
            if (self.seconds_per_beat < 0 or !std.math.isNormal(self.seconds_per_beat)) {
                return self.seconds_offset;
            }
            const seconds = (beats - self.beats_offset) * self.seconds_per_beat + self.seconds_offset;
            if (seconds < self.seconds_offset) {
                return self.seconds_offset;
            }
            return seconds;
        }

        /// Convert `seconds` into beats.
        ///
        /// Inverse operation of `convertBeatToSeconds`.
        ///
        /// **(It can only guarantee accuracy from the last object until the next object)**
        pub inline fn convertSecondsToBeats(self: @This(), seconds: Object.Time) Object.Time {
            if (self.seconds_per_beat < 0 or !std.math.isNormal(self.seconds_per_beat)) {
                return self.beats_offset;
            }
            if (seconds < self.seconds_offset) {
                return self.beats_offset;
            }
            const beats = (seconds - self.seconds_offset) / self.seconds_per_beat + self.beats_offset;
            return beats;
        }

        /// Process objects and update
        pub fn update(self: *@This(), conductor: Conductor, current_seconds: Object.Time, is_audio_thread: bool) void {
            self.updateBeat(current_seconds);
            for (conductor.objects[self.next_object_to_process..], self.next_object_to_process..) |object, i| {
                if (self.beat < object.beat) {
                    break;
                }
                self.next_object_to_process = i + 1;
                object.process(object, self);
                if (is_audio_thread) {
                    object.processAudio(object);
                }
                self.updateBeat(current_seconds);
            }
        }
    };
};
