const std = @import("std");

const ScrollDirection = @import("../graphics.zig").ScrollDirection;

const ChartType = @import("conductor.zig").ChartType;
const State = @import("conductor.zig").Conductor.State;

const Renderer = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
}).SDL_Renderer;

fn emptyDestroy(_: Object, _: std.mem.Allocator) void {}
fn emptyProcess(_: Object, _: *State) void {}
fn emptyProcessAudio(_: Object) void {}
fn emptyHit(_: Object) void {}
fn emptyRender(
    _: Object,
    _: Object.Position,
    _: Object.Position,
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
    destroy: *const fn (object: @This(), allocator: std.mem.Allocator) void = &emptyDestroy,

    /// Called when processing, loading and running gameplay.
    /// Will run at the "perfect" time for the object.
    ///
    /// For example, a BPM object would change the bpm in here,
    /// while a BGM note object would do nothing in here (so it should be null).
    process: *const fn (object: @This(), state: *State) void = emptyProcess,

    /// Called when running gameplay on the audio thread.
    /// Will run at the "perfect" time for the object.
    ///
    /// For example, a BPM object would do nothing in here (so it should be null),
    /// while a BGM note object would play their keysound.
    processAudio: *const fn (object: @This()) void = emptyProcessAudio,

    /// Called when running gameplay.
    /// Will run at the time the player hits this object.
    hit: *const fn (
        object: @This(),
    ) void = emptyHit,

    /// Called when running gameplay.
    /// Will render the object on screen.
    // TODO: Make this better probably
    render: *const fn (
        object: @This(),
        object_position: Object.Position,
        current_position: Object.Position,
        chart_type: ChartType,
        scroll_speed: Object.Position,
        scroll_direction: ScrollDirection,
        renderer: *Renderer,
    ) error{SdlError}!void = emptyRender,

    /// Use this function for sorting lists of objects
    pub fn lessThanFn(_: void, lhs: @This(), rhs: @This()) bool {
        if (lhs.beat == rhs.beat) {
            return lhs.priority < rhs.priority;
        }
        return lhs.beat < rhs.beat;
    }
};
