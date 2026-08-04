const std = @import("std");
const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "");
    @cInclude("SDL3/SDL.h");
});

pub fn main() !void {
    // 1. Initialize SDL Video Subsystem
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.log.err("SDL Init Failed: {s}", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // 2. Create the window
    const window = c.SDL_CreateWindow("Zig 0.16.0 + SDL3 Window", 800, 600, 0) orelse {
        std.log.err("Window Creation Failed: {s}", .{c.SDL_GetError()});
        return error.WindowCreationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // 3. Create the 2D Renderer
    const renderer = c.SDL_CreateRenderer(window, null) orelse {
        std.log.err("Renderer Creation Failed: {s}", .{c.SDL_GetError()});
        return error.RendererCreationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    std.debug.print("Window and Renderer created successfully!\n", .{});

    // 4. Application Loop State
    var running = true;
    var event: c.SDL_Event = undefined;

    // 5. Main Game / Application Loop
    while (running) {
        // Poll for pending application events
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                // Handle Window Close button ('X' button)
                c.SDL_EVENT_QUIT => {
                    running = false;
                },
                // Handle Key Presses
                c.SDL_EVENT_KEY_DOWN => {
                    if (event.key.scancode == c.SDL_SCANCODE_ESCAPE) {
                        running = false;
                    }
                },
                else => {},
            }
        }

        // --- Render Code ---
        // Set clear color to a nice dark slate blue (R, G, B, A)
        _ = c.SDL_SetRenderDrawColor(renderer, 30, 40, 60, 255);
        _ = c.SDL_RenderClear(renderer);

        // --- DRAW HELLO TEXT ---
        // Set text drawing color to bright white
        _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
        // Scale rendering if you want larger debug text (e.g., 2.0x scale)
        _ = c.SDL_SetRenderScale(renderer, 2.0, 2.0);
        // Draw string at coordinate X: 50, Y: 50 (divided by scale if scaled)
        _ = c.SDL_RenderDebugText(renderer, 50, 50, "Hello 2D Text World!");
        // Reset scale back to normal so your other shapes don't get skewed
        _ = c.SDL_SetRenderScale(renderer, 1.0, 1.0);

        // Present the updated backbuffer to the screen
        _ = c.SDL_RenderPresent(renderer);

        // Minor delay to stop the CPU from pinning at 100%
        c.SDL_Delay(1);
    }

    std.debug.print("Application exited cleanly.\n", .{});
}
