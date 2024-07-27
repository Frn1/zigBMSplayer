const std = @import("std");

const c = @import("consts.zig");
const gfx = @import("graphics.zig");

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});
const ma = @cImport({
    @cDefine("MINIAUDIO_IMPLEMENTATION", {});
    @cInclude("miniaudio.h");
});

pub const NormalNoteTypeTag = enum { normal, mine, hidden };

pub const NormalNoteType = union(NormalNoteTypeTag) {
    normal,
    /// Points of damage to do if the player hits this mine.
    /// Infinity means instant death.
    mine: f32,
    hidden,
};

pub const LongNoteType = enum { normal, roll, mine };

pub const NoteTypeTag = enum { normal, ln_head, ln_tail, bgm };

pub const NoteType = union(NoteTypeTag) {
    normal: NormalNoteType,
    /// value is the index of the ln_tail for this head
    ln_head: usize,
    ln_tail: LongNoteType,
    bgm,
};

pub const Note = struct {
    beat: f80,
    lane: u7,
    keysound_id: u11,
    type: NoteType,

    pub fn lessThanFn(ctx: void, lhs: @This(), rhs: @This()) bool {
        _ = ctx;
        return lhs.beat < rhs.beat;
    }
};

pub const SegmentTypeTag = enum { bpm, scroll, stop, barline };

pub const SegmentType = union(SegmentTypeTag) { bpm: f64, scroll: f64, stop: f80, barline };

pub const Segment = struct {
    beat: f80,
    type: SegmentType,

    pub fn lessThanFn(ctx: void, lhs: @This(), rhs: @This()) bool {
        _ = ctx;
        return lhs.beat < rhs.beat;
    }
};

pub const Conductor = struct {
    chart_type: enum { beat7k, beat5k, beat14k, beat10k } = .beat5k,

    notes: []Note,
    segments: []Segment,

    objects: []Object = undefined,

    // 1295 = ZZ = max value in BMS
    keysounds: [1295]?*ma.ma_sound = .{null} ** 1295,

    pub const ObjectType = enum { Note, Segment };

    pub const Object = struct {
        obj_type: ObjectType,
        obj_beat: f80,
        index: usize,

        fn lessThanFn(ctx: Conductor, lhs: @This(), rhs: @This()) bool {
            if (lhs.obj_beat == rhs.obj_beat) {
                if (rhs.obj_type == ObjectType.Segment) {
                    // Make stops go at the end of the beat
                    // This is cuz EVERYTHING at this beat takes priority before stopping
                    return ctx.segments[rhs.index].type == SegmentTypeTag.stop;
                }
                return false;
            }
            return lhs.obj_beat < rhs.obj_beat;
        }
    };

    pub fn sortNotes(self: Conductor) void {
        std.sort.heap(Note, self.notes, {}, Note.lessThanFn);
    }

    pub fn sortSegments(self: Conductor) void {
        std.sort.heap(Segment, self.segments, {}, Segment.lessThanFn);
    }

    pub fn sortObjects(self: Conductor) void {
        std.sort.heap(
            Object,
            self.objects,
            self,
            Object.lessThanFn,
        );
    }

    pub fn createObjects(self: *@This(), allocator: std.mem.Allocator) !void {
        self.objects = try allocator.alloc(Object, self.notes.len + self.segments.len);

        for (self.notes, 0.., 0..) |note, original_i, objects_i| {
            self.objects[objects_i].obj_beat = note.beat;
            self.objects[objects_i].obj_type = ObjectType.Note;
            self.objects[objects_i].index = original_i;
        }

        for (self.segments, 0.., self.notes.len..) |segment, original_i, objects_i| {
            self.objects[objects_i].obj_beat = segment.beat;
            self.objects[objects_i].obj_type = ObjectType.Segment;
            self.objects[objects_i].index = original_i;
        }

        self.sortObjects();
    }

    pub fn deleteObjects(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.objects);
    }

    pub fn calculateObjectTimesInSeconds(self: @This(), allocator: std.mem.Allocator) ![]f80 {
        var output = try allocator.alloc(f80, self.objects.len);

        var state = ConductorState{};

        for (self.objects, 0..self.objects.len) |object, index| {
            const time = state.calculateSecondsFromBeatApprox(object.obj_beat);
            output[index] = time;
            state.process(self, time);
        }

        return output;
    }

    pub fn calculateVisualBeats(self: @This(), allocator: std.mem.Allocator) ![]struct { visual_beat: f80, ln_tail_obj_index: ?usize = null } {
        const ResultStruct = @typeInfo(
            @typeInfo(@typeInfo(@TypeOf(calculateVisualBeats)).Fn.return_type.?).ErrorUnion.payload,
        ).Pointer.child;

        var output: []ResultStruct = try allocator.alloc(ResultStruct, self.objects.len);

        var state = ConductorState{};

        for (self.objects, 0..self.objects.len) |object, index| {
            const time = state.calculateSecondsFromBeatApprox(object.obj_beat);
            state.process(self, time);
            output[index] = .{
                .visual_beat = state.calculateVisualPosition(object.obj_beat),
            };
            if (object.obj_type == ObjectType.Note) {
                if (self.notes[object.index].type == NoteTypeTag.ln_head) {
                    const ln_tail_note_index = self.notes[object.index].type.ln_head;
                    for (self.objects, 0..) |object2, index2| {
                        if (object2.obj_type == ObjectType.Note and object2.index == ln_tail_note_index) {
                            output[index].ln_tail_obj_index = index2;
                            break;
                        }
                    }
                }
            }
        }

        return output;
    }
};

pub const ConductorState = struct {
    /// Last processed object index
    next_object_to_process: usize = 0,

    /// Current seconds per beat (basically BPM)
    current_sec_per_beat: f80 = std.math.inf(f80),
    /// seconds to subtruct from the time
    sec_offset: f80 = 0,
    /// beats to add when calculating current_beat
    beat_offset: f80 = 0,

    /// beats to subtract when calculating visual position
    visual_beats_offset: f80 = 0,
    /// pos to add when calculating visual position
    visual_pos_offset: f80 = 0,
    /// current scroll multiplier (decimal number)
    current_scroll_mul: f80 = 1.0,

    /// The current beat, should always move foward and never go back in time
    current_beat: f80 = 0,

    /// Recalculate the current beat
    pub inline fn updateCurrentbeat(self: *@This(), current_sec: f80) void {
        self.current_beat = self.calculateBeatFromSecondsApprox(current_sec);
    }

    // Calculate the visual position at that beat
    pub inline fn calculateVisualPosition(self: @This(), current_beat: f80) f80 {
        return (current_beat - self.visual_beats_offset) * self.current_scroll_mul + self.visual_pos_offset;
    }

    // Calculate the second from a time in beats approximately
    // (It can only guarantee accuracy until the next segment)
    pub inline fn calculateSecondsFromBeatApprox(self: @This(), time_beats: f80) f80 {
        if (self.current_sec_per_beat < 0 or !std.math.isNormal(self.current_sec_per_beat)) {
            return self.sec_offset;
        }
        const time_secs = (time_beats - self.beat_offset) * self.current_sec_per_beat + self.sec_offset;
        if (time_secs < self.sec_offset) {
            return self.sec_offset;
        }
        return time_secs;
    }

    // Calculate the beat from a time in seconds approximately
    // (It can only guarantee accuracy until the next segment)
    pub inline fn calculateBeatFromSecondsApprox(self: @This(), time_secs: f80) f80 {
        if (self.current_sec_per_beat < 0 or !std.math.isNormal(self.current_sec_per_beat)) {
            return self.beat_offset;
        }
        if (time_secs < self.sec_offset) {
            return self.beat_offset;
        }
        const time_beats = (time_secs - self.sec_offset) / self.current_sec_per_beat + self.beat_offset;
        return time_beats;
    }

    /// Process events and update the conductor
    pub fn process(self: *@This(), conductor: Conductor, current_sec: f80) void {
        self.updateCurrentbeat(current_sec);
        for (conductor.objects[self.next_object_to_process..], self.next_object_to_process..) |object, i| {
            if (self.current_beat < object.obj_beat) {
                break;
            }
            defer self.next_object_to_process = i + 1;
            if (object.obj_type == Conductor.ObjectType.Segment) {
                const segment = conductor.segments[object.index];
                switch (segment.type) {
                    SegmentTypeTag.bpm => |new_bpm| {
                        if (self.current_sec_per_beat < 0 or !std.math.isNormal(self.current_sec_per_beat)) {
                            self.sec_offset = 0;
                            self.beat_offset = 0;
                            self.current_sec_per_beat = @floatCast(60.0 / new_bpm);
                        } else {
                            // Calculate the time the bpm change should've occured
                            self.sec_offset = self.calculateSecondsFromBeatApprox(segment.beat);
                            self.beat_offset = segment.beat;
                            self.current_sec_per_beat = @floatCast(60.0 / new_bpm);
                        }
                    },
                    SegmentTypeTag.scroll => |new_scroll| {
                        self.visual_pos_offset = self.calculateVisualPosition(segment.beat);
                        self.visual_beats_offset = segment.beat;
                        self.current_scroll_mul = @floatCast(new_scroll);
                    },
                    SegmentTypeTag.stop => |stopped_beats| {
                        self.sec_offset = self.calculateSecondsFromBeatApprox(
                            segment.beat + @as(f80, @floatCast(stopped_beats)),
                        );
                        self.beat_offset = segment.beat;
                        self.visual_pos_offset = self.calculateVisualPosition(segment.beat);
                        self.visual_beats_offset = segment.beat;
                    },
                    else => {},
                }
                self.updateCurrentbeat(current_sec);
            }
        }
    }
};
