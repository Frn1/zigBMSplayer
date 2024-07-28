const std = @import("std");

const ScrollDirection = @import("../graphics.zig").ScrollDirection;

const State = @import("conductor.zig").Conductor.State;

const Renderer = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
}).SDL_Renderer;

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

    /// Pointer to a function to initialize `parameters`
    /// and do other work before starting the game.
    ///
    /// Called when loading
    init: ?*const fn (self: *@This(), allocator: std.mem.Allocator) error{
        OutOfMemory,
        InvalidParameters,
    }!void = null,

    /// Pointer to a function to destroy `parameters`
    /// and everything created in init
    ///
    /// Called when exiting
    destroy: ?*const fn (self: @This(), allocator: std.mem.Allocator) void = null,

    /// Called when processing/loading/running gameplay.
    /// Will run at the "perfect" time for the object.
    ///
    /// For example, a BPM object would change the bpm in here,
    /// while a BGM note object would do nothing in here (so it should be null).
    process: ?*const fn (self: @This(), state: *State) void = null,

    /// Called when running gameplay.
    /// Will run at the "perfect" time for the object.
    ///
    /// For example, a BPM object would do nothing in here (so it should be null),
    /// while a BGM note object would play their keysound.
    processGameplay: ?*const fn (self: @This()) void = null,

    /// Called when running gameplay.
    /// Will run at the time the player hits this object.
    ///
    /// TODO: Ratings
    hit: ?*const fn (
        self: @This(),
        perfect_hit_time: Object.Time,
        actual_hit_time: Object.Time,
    ) void = null,

    /// Called when running gameplay.
    /// Will render the object on screen.
    // TODO: Make this better probably
    render: ?*const fn (
        self: @This(),
        object_position: Object.Position,
        current_position: Object.Position,
        scroll_speed: Object.Position,
        scroll_direction: ScrollDirection,
        renderer: *Renderer,
    ) error{SdlError}!void = null,

    /// Use this function for sorting lists of objects
    pub fn lessThanFn(_: void, lhs: @This(), rhs: @This()) bool {
        if (lhs.beat == rhs.beat) {
            return lhs.priority < rhs.priority;
        }
        return lhs.beat < rhs.beat;
    }
};
