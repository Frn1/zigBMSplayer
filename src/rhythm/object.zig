const std = @import("std");

const ScrollDirection = @import("../graphics.zig").ScrollDirection;

const ChartType = @import("conductor.zig").ChartType;
const State = @import("conductor.zig").Conductor.State;
const Lane = @import("objects/note.zig").Lane;

const Renderer = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
}).SDL_Renderer;

fn emptyDestroy(_: Object, _: std.mem.Allocator) void {}
fn emptyProcess(_: Object, _: *State) void {}
fn emptyProcessAudio(_: Object) void {}
fn emptyHit(_: Object) void {}
fn emptyCanHit(_: Object, _: Lane) bool {
    return false;
}
fn emptyLongHit(_: Object, _: Lane) ?usize {
    return null;
}
fn emptyRender(
    _: Object,
    _: Object.Position,
    _: Object.Position,
    _: []Object.Position,
    _: ChartType,
    _: Object.Position,
    _: ScrollDirection,
    _: *Renderer,
) !void {}

pub const Object = struct {
    pub const Time = f80;
    pub const Position = f32;

    /// Rhythmic time that the object would be hit at
    beat: Time,

    /// Priority used for sorting when objects have the same `beat`
    ///
    /// Lower comes first while higher comes after
    priority: i8 = 0,

    /// Extra parameters for this object
    parameters: *anyopaque = undefined,

    /// Pointer to a function to destroy `parameters`
    /// and everything created in init
    ///
    /// Called when exiting
    destroy: *const fn (self: @This(), allocator: std.mem.Allocator) void = &emptyDestroy,

    /// Called when processing, loading and running gameplay.
    /// Will run at the "perfect" time for the object.
    ///
    /// For example, a BPM object would change the bpm in here,
    /// while a BGM note object would do nothing in here (so it should be null).
    process: *const fn (self: @This(), state: *State) void = emptyProcess,

    /// Called when running game play on the audio thread.
    /// Will run at the "perfect" time for the object.
    ///
    /// For example, a BPM object would do nothing in here (so it should be null),
    /// while a BGM note object would play their keysound.
    processAudio: *const fn (self: @This()) void = emptyProcessAudio,

    /// This function is used to judge notes.
    ///
    /// It should return true when an object can be hit with that lane, and false when it cant
    hit: *const fn (self: @This()) void = emptyHit,

    /// This function is used to judge notes.
    ///
    /// It should return true when an object can be hit with that lane, and false when it cant
    canHit: *const fn (self: @This(), lane: Lane) bool = emptyCanHit,

    /// This function is used to judge notes.
    /// It should return the tail object index when the note
    /// can be hit with that lane or `null` if thats not the case.
    longHit: *const fn (self: @This(), lane: Lane) ?usize = emptyLongHit,

    /// Called when running gameplay.
    /// Will render the object on screen.
    // TODO: Make this better probably
    render: *const fn (
        self: @This(),
        position: Object.Position,
        current_position: Object.Position,
        all_positions: []Object.Position,
        chart_type: ChartType,
        scroll_speed: Object.Position,
        scroll_direction: ScrollDirection,
        renderer: *Renderer,
    ) error{SdlError}!void = emptyRender,

    /// Use this function to pointer cast the parameters
    pub inline fn castParameters(comptime T: type, ptr: *anyopaque) *T {
        return @as(*T, @alignCast(@ptrCast(ptr)));
    }

    /// Use this function for sorting lists of objects
    pub fn lessThanFn(_: void, lhs: @This(), rhs: @This()) bool {
        if (lhs.beat == rhs.beat) {
            return lhs.priority < rhs.priority;
        }
        return lhs.beat < rhs.beat;
    }
};
