const std = @import("std");

const gfx = @import("../../graphics.zig");
const c = @import("../../consts.zig");

const sdlAssert = @import("../../utils.zig").sdlAssert;

const State = @import("../conductor.zig").Conductor.State;
const Object = @import("../object.zig").Object;

const ma = @cImport({
    @cDefine("MINIAUDIO_IMPLEMENTATION", {});
    @cInclude("miniaudio.h");
});

pub const Lane = u8;
pub const Keysound = *ma.ma_sound;

const Parameters = ?Keysound;

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

fn destroy(object: Object, allocator: std.mem.Allocator) void {
    allocator.destroy(@as(*Parameters, @alignCast(@ptrCast(object.parameters))));
}

fn processAudio(object: Object) void {
    const parameters = @as(*Parameters, @alignCast(@ptrCast(object.parameters)));
    if (parameters.* != null) {
        _ = ma.ma_sound_seek_to_pcm_frame(parameters.*, 0);
        _ = ma.ma_sound_start(parameters.*);
    }
}

/// Creates a Note object.
///
/// **Caller is responsible of calling `destroy` to destroy the object.
/// (If it's not null)**
///
/// **Note: This is NOT the same as calling `allocator.destroy`.**
pub fn create(allocator: std.mem.Allocator, beat: Object.Time, sound: ?Keysound) !Object {
    var object = Object{
        .beat = beat,
        .destroy = destroy,
        .processAudio = processAudio,
    };
    object.parameters = @ptrCast(try allocator.create(Parameters));
    const params = @as(*Parameters, @alignCast(@ptrCast(object.parameters)));
    params.* = sound;

    return object;
}
