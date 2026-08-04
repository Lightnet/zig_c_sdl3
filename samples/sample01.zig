const std = @import("std");
const Io = std.Io;

// Import SDL3 directly inside your source file
const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", ""); // Prevents SDL from overriding main
    @cInclude("SDL3/SDL.h");
});

pub fn main(init: std.process.Init) !void {
    _ = init;
    // Prints to stderr, unbuffered, ignoring potential errors.
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.log.err("SDL Init Failed: {s}", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Zig 0.16.0 + SDL3", 800, 600, 0) orelse return error.WindowCreationFailed;
    defer c.SDL_DestroyWindow(window);

    std.debug.print("SDL3 Window created successfully!\n", .{});
}
