const std = @import("std");
const math = @import("math.zig");

const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "1");
    @cInclude("SDL3/SDL.h");
});

// Structural layout matching SDL_Vertex
const Vertex = struct {
    position: c.SDL_FPoint,
    color: c.SDL_FColor,
};

pub fn main() !void {
    // 1. Force Direct3D 11 backend
    _ = c.SDL_SetHint(c.SDL_HINT_RENDER_DRIVER, "direct3d11");

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.log.err("SDL Initialization Failed: {s}", .{c.SDL_GetError()});
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow(
        "SDL3 Accelerated 3D Cube - Zig 0.16.0",
        800,
        600,
        c.SDL_WINDOW_RESIZABLE,
    ) orelse {
        std.log.err("Window creation failed: {s}", .{c.SDL_GetError()});
        return error.WindowCreationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, null) orelse {
        std.log.err("Renderer creation failed: {s}", .{c.SDL_GetError()});
        return error.RendererCreationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    std.log.info("Active Backend: {s}", .{c.SDL_GetRendererName(renderer)});

    // 2. Define standard 3D Cube Corner Positions (-0.5 to +0.5 space)
    const cube_vertices = [_]math.Vec3{
        .{ .x = -0.5, .y = -0.5, .z = 0.5 }, // 0
        .{ .x = 0.5, .y = -0.5, .z = 0.5 }, // 1
        .{ .x = 0.5, .y = 0.5, .z = 0.5 }, // 2
        .{ .x = -0.5, .y = 0.5, .z = 0.5 }, // 3
        .{ .x = -0.5, .y = -0.5, .z = -0.5 }, // 4
        .{ .x = 0.5, .y = -0.5, .z = -0.5 }, // 5
        .{ .x = 0.5, .y = 0.5, .z = -0.5 }, // 6
        .{ .x = -0.5, .y = 0.5, .z = -0.5 }, // 7
    };

    // Index mappings to draw the 12 edges (24 index lines) of a wireframe cube
    const cube_indices = [_]u32{
        0, 1, 1, 2, 2, 3, 3, 0, // Front Face
        4, 5, 5, 6, 6, 7, 7, 4, // Back Face
        0, 4, 1, 5, 2, 6, 3, 7, // Connecting Edges
    };

    // Vertex Colors (RGBA normalized values)
    const vertex_colors = [_]c.SDL_FColor{
        .{ .r = 1, .g = 0, .b = 0, .a = 1 },
        .{ .r = 0, .g = 1, .b = 0, .a = 1 },
        .{ .r = 0, .g = 0, .b = 1, .a = 1 },
        .{ .r = 1, .g = 1, .b = 0, .a = 1 },
        .{ .r = 1, .g = 0, .b = 1, .a = 1 },
        .{ .r = 0, .g = 1, .b = 1, .a = 1 },
        .{ .r = 1, .g = 1, .b = 1, .a = 1 },
        .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    var quit = false;
    var rotation: f32 = 0.0;

    // 3. Application Execution Loop
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) quit = true;
        }

        // Increment rotation over time
        rotation += 0.015;

        // Fetch current screen boundaries for dynamic projection scaling
        var w: c_int = 800;
        var h: c_int = 600;
        _ = c.SDL_GetWindowSize(window, &w, &h);
        const width_f = @as(f32, @floatFromInt(w));
        const height_f = @as(f32, @floatFromInt(h));

        // Create standard Projection and View Matrix states manually
        const proj = math.Mat4.perspective(60.0 * (std.math.pi / 180.0), width_f / height_f, 0.1, 100.0);
        const rot_x = math.Mat4.rotate(rotation, .{ .x = 1.0, .y = 0.0, .z = 0.0 });
        const rot_y = math.Mat4.rotate(rotation * 0.5, .{ .x = 0.0, .y = 1.0, .z = 0.0 });

        // Clear Screen Buffer
        _ = c.SDL_SetRenderDrawColor(renderer, 20, 20, 30, 255);
        _ = c.SDL_RenderClear(renderer);

        // Project and Transform 3D Coordinates into 2D Screen Space
        var projected_vertices: [8]Vertex = undefined;

        for (cube_vertices, 0..) |v, i| {
            // Apply rotations
            const pos = v;

            // Basic manual matrix multiplications for rotation/projection pipeline transforms
            const x1 = rot_y.m[0][0] * pos.x + rot_y.m[0][1] * pos.y + rot_y.m[0][2] * pos.z;
            const y1 = rot_y.m[1][0] * pos.x + rot_y.m[1][1] * pos.y + rot_y.m[1][2] * pos.z;
            const z1 = rot_y.m[2][0] * pos.x + rot_y.m[2][1] * pos.y + rot_y.m[2][2] * pos.z;

            const x2 = rot_x.m[0][0] * x1 + rot_x.m[0][1] * y1 + rot_x.m[0][2] * z1;
            const y2 = rot_x.m[1][0] * x1 + rot_x.m[1][1] * y1 + rot_x.m[1][2] * z1;
            var z2 = rot_x.m[2][0] * x1 + rot_x.m[2][1] * y1 + rot_x.m[2][2] * z1;

            // Translate the cube back along the Z-axis so it is visible to our camera perspective
            z2 -= 2.0;

            // Apply Projection Matrix calculations
            const clip_w = -z2;
            const screen_x = ((proj.m[0][0] * x2) / clip_w + 1.0) * 0.5 * width_f;
            const screen_y = ((proj.m[1][1] * y2) / clip_w + 1.0) * 0.5 * height_f;

            projected_vertices[i] = .{
                .position = .{ .x = screen_x, .y = screen_y },
                .color = vertex_colors[i],
            };
        }

        // 4. Render the Wireframe lines utilizing DX11 hardware-accelerated processing calls
        var idx: usize = 0;
        while (idx < cube_indices.len) : (idx += 2) {
            const v0 = projected_vertices[cube_indices[idx]];
            const v1 = projected_vertices[cube_indices[idx + 1]];

            // Convert colors seamlessly back into immediate rendering colors
            _ = c.SDL_SetRenderDrawColor(
                renderer,
                @as(u8, @intFromFloat(v0.color.r * 255.0)),
                @as(u8, @intFromFloat(v0.color.g * 255.0)),
                @as(u8, @intFromFloat(v0.color.b * 255.0)),
                255,
            );

            _ = c.SDL_RenderLine(renderer, v0.position.x, v0.position.y, v1.position.x, v1.position.y);
        }

        // Present Render Targets
        _ = c.SDL_RenderPresent(renderer);
        c.SDL_Delay(16); // Target ~60FPS roughly
    }
}
