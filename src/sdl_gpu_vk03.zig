const std = @import("std");
const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "");
    @cInclude("SDL3/SDL.h");
});

const Vertex = struct {
    pos: [3]f32,
    color: [3]f32,
};

const UniformBufferObject = struct {
    mvp: [4][4]f32,
};

// Vulkan uniforms require strict 16-byte alignment per matrix column block
pub const Mat4 = extern struct {
    data: [4][4]f32 align(16),
};

fn loadShader(
    io: std.Io,
    device: *c.SDL_GPUDevice,
    path: []const u8,
    stage: c.SDL_GPUShaderStage,
) !*c.SDL_GPUShader {
    const cwd = std.Io.Dir.cwd();
    var file = try cwd.openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);

    const stat = try file.stat(io);
    const code = try std.heap.page_allocator.alloc(u8, stat.size);
    defer std.heap.page_allocator.free(code);

    _ = try file.readPositionalAll(io, code, 0);

    var info = std.mem.zeroes(c.SDL_GPUShaderCreateInfo);
    info.code_size = code.len;
    info.code = code.ptr;
    info.entrypoint = "main";
    info.format = c.SDL_GPU_SHADERFORMAT_SPIRV;
    info.stage = stage;

    if (stage == c.SDL_GPU_SHADERSTAGE_VERTEX) {
        info.num_uniform_buffers = 1;
    }

    return c.SDL_CreateGPUShader(device, &info) orelse {
        std.log.err("Failed to create shader {s}: {s}", .{ path, c.SDL_GetError() });
        return error.ShaderCreationFailed;
    };
}

// fn createMVP(angle: f32) [4][4]f32 {
//     const rad = angle * (std.math.pi / 180.0);
//     const c_a = @cos(rad);
//     const s_a = @sin(rad);

//     // Improved matrix - should show a nice rotating cube
//     return .{
//         .{ 1.5 * c_a, 0.0, 1.5 * s_a, 0.0 },
//         .{ 0.0, 1.5, 0.0, 0.0 },
//         .{ -0.8 * s_a, 0.0, 0.8 * c_a, -0.4 },
//         .{ 0.0, 0.0, -3.0, 1.0 },
//     };
// }

// fn createMVP(angle: f32) [4][4]f32 {
//     const rad = angle * (std.math.pi / 180.0);
//     const cc = @cos(rad);
//     const s = @sin(rad);
//     // Model: rotate around Y
//     const model = [4][4]f32{
//         .{ cc, 0.0, s, 0.0 },
//         .{ 0.0, 1.0, 0.0, 0.0 },
//         .{ -s, 0.0, cc, 0.0 },
//         .{ 0.0, 0.0, 0.0, 1.0 },
//     };
//     // View: move camera back along Z
//     const view_z = -4.0;
//     const view = [4][4]f32{
//         .{ 1, 0, 0, 0 },
//         .{ 0, 1, 0, 0 },
//         .{ 0, 0, 1, view_z },
//         .{ 0, 0, 0, 1 },
//     };
//     // Simple Perspective Projection
//     const aspect = 800.0 / 600.0;
//     const fov_scale = 1.0; // roughly 60-70° FOV
//     const near = 0.5;
//     const far = 20.0;
//     const proj = [4][4]f32{
//         .{ fov_scale / aspect, 0.0, 0.0, 0.0 },
//         .{ 0.0, fov_scale, 0.0, 0.0 },
//         .{ 0.0, 0.0, (far + near) / (near - far), (2.0 * far * near) / (near - far) },
//         .{ 0.0, 0.0, -1.0, 0.0 },
//     };
//     // proj * view * model
//     var mvp: [4][4]f32 = .{ .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 } };
//     // First view * model
//     var tmp: [4][4]f32 = undefined;
//     for (0..4) |i| for (0..4) |j| {
//         tmp[i][j] = 0;
//         for (0..4) |k| tmp[i][j] += view[i][k] * model[k][j];
//     };
//     // Then proj * tmp
//     for (0..4) |i| for (0..4) |j| {
//         for (0..4) |k| mvp[i][j] += proj[i][k] * tmp[k][j];
//     };
//     return mvp;
// }

//vulkan
// pub fn createMVP(angle_deg: f32, cam_x: f32, cam_y: f32, cam_z: f32) Mat4 {
//     const rad = angle_deg * (std.math.pi / 180.0);
//     const cc = @cos(rad);
//     const s = @sin(rad);

//     // Model: Rotate Y
//     const model = [4][4]f32{
//         .{ cc, 0.0, s, 0.0 },
//         .{ 0.0, 1.0, 0.0, 0.0 },
//         .{ -s, 0.0, cc, 0.0 },
//         .{ 0.0, 0.0, 0.0, 1.0 },
//     };

//     // View: Invert camera position coordinates for world translation
//     const view = [4][4]f32{
//         .{ 1.0, 0.0, 0.0, 0.0 },
//         .{ 0.0, 1.0, 0.0, 0.0 },
//         .{ 0.0, 0.0, 1.0, 0.0 },
//         .{ -cam_x, -cam_y, -cam_z, 1.0 },
//     };

//     // Projection: Explicitly built for Vulkan's [0.0 to 1.0] Z depth buffer range
//     const aspect = 800.0 / 600.0;
//     const fov_scale = 1.732; // ~60 degree horizontal Field of View
//     const near = 0.1;
//     const far = 100.0;
//     const proj = [4][4]f32{
//         .{ fov_scale / aspect, 0.0, 0.0, 0.0 },
//         .{ 0.0, fov_scale, 0.0, 0.0 },
//         .{ 0.0, 0.0, far / (near - far), -1.0 },
//         .{ 0.0, 0.0, (far * near) / (near - far), 0.0 },
//     };

//     // Row-Major Matrix multiplication calculations
//     var tmp: [4][4]f32 = undefined;
//     for (0..4) |i| {
//         for (0..4) |j| {
//             var sum: f32 = 0.0;
//             for (0..4) |k| {
//                 sum += view[i][k] * model[k][j];
//             }
//             tmp[i][j] = sum;
//         }
//     }

//     var row_major_mvp: [4][4]f32 = undefined;
//     for (0..4) |i| {
//         for (0..4) |j| {
//             var sum: f32 = 0.0;
//             for (0..4) |k| {
//                 sum += proj[i][k] * tmp[k][j];
//             }
//             row_major_mvp[i][j] = sum;
//         }
//     }

//     // CRITICAL VULKAN STEP: Transpose the final Row-Major matrix
//     // into Column-Major memory storage so SPIR-V maps it correctly.
//     var final_mvp: Mat4 = undefined;
//     for (0..4) |i| {
//         for (0..4) |j| {
//             final_mvp.data[i][j] = row_major_mvp[j][i];
//         }
//     }

//     // MANUALLY SHRINK THE ENTIRE OUTPUT SCENE BY 50%
//     // final_mvp.data[0][0] *= 0.001; // Scale X
//     // final_mvp.data[1][1] *= 0.001; // Scale Y
//     // final_mvp.data[2][2] *= 0.001; // Scale Z

//     // MANUALLY OVERRIDE CAMERA TRANSLATION (Column 3 holds X, Y, Z translation)
//     // final_mvp.data[3][0] = -10.0; // Manually shift X axis (Left / Right)
//     // final_mvp.data[3][1] = -10.0; // Manually shift Y axis (Up / Down)
//     // final_mvp.data[3][2] = -10.0; // Manually shift Z axis (Push camera back to 5.0)
//     // final_mvp.data[3][3] = 1.0; // W component must remain 1.0

//     // final_mvp.data[3][1] = 0.01;

//     final_mvp.data[3][2] = -10.0; // Manually shift Z axis (Push camera back to 5.0)

//     return final_mvp;
// }

pub fn createMVP(angle_deg: f32) Mat4 {
    const rad = angle_deg * (@as(f32, @floatCast(std.math.pi)) / 180.0);
    const cos_angle = @cos(rad);
    const sin_angle = @sin(rad);

    // 1. Model Matrix: Rotate Y (Column-Major [col][row])
    const model = Mat4{
        .data = .{
            .{ cos_angle, 0.0, -sin_angle, 0.0 }, // Col 0
            .{ 0.0, 1.0, 0.0, 0.0 }, // Col 1
            .{ sin_angle, 0.0, cos_angle, 0.0 }, // Col 2
            .{ 0.0, 0.0, 0.0, 1.0 }, // Col 3
        },
    };

    // 2. View Matrix: Position camera 5 units back on Z axis
    const view = Mat4{ .data = .{
        .{ 1.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, -5.0, 1.0 },
    } };

    // 3. Projection Matrix: Vulkan clip space [0.0 to 1.0] Z depth
    const aspect: f32 = 800.0 / 600.0;
    const fov_scale: f32 = 1.0 / @tan(30.0 * (@as(f32, @floatCast(std.math.pi)) / 180.0));
    const near: f32 = 0.1;
    const far: f32 = 100.0;

    const proj = Mat4{
        .data = .{
            .{ fov_scale / aspect, 0.0, 0.0, 0.0 },
            .{ 0.0, -fov_scale, 0.0, 0.0 }, // Negative Y handles Vulkan screen space
            .{ 0.0, 0.0, far / (near - far), -1.0 },
            .{ 0.0, 0.0, (far * near) / (near - far), 0.0 },
        },
    };

    // 4. Matrix Multiplication: Order is Proj * View * Model
    const mv = multiplyMatrices(view, model);
    return multiplyMatrices(proj, mv);
}

pub fn createMVP_Move(angle_deg: f32, pos_x: f32, pos_y: f32, pos_z: f32) Mat4 {
    const rad = angle_deg * (@as(f32, @floatCast(std.math.pi)) / 180.0);
    const cos_angle = @cos(rad);
    const sin_angle = @sin(rad);

    // 1. Model Matrix: Rotate Y AND Translate (Column-Major [col][row])
    const model = Mat4{
        .data = .{
            .{ cos_angle, 0.0, -sin_angle, 0.0 }, // Col 0: X-axis basis
            .{ 0.0, 1.0, 0.0, 0.0 }, // Col 1: Y-axis basis
            .{ sin_angle, 0.0, cos_angle, 0.0 }, // Col 2: Z-axis basis
            .{ pos_x, pos_y, pos_z, 1.0 }, // Col 3: Translation Vector (X, Y, Z, W)
        },
    };

    // 2. View Matrix: Position camera 5 units back on Z axis
    const view = Mat4{
        .data = .{
            .{ 1.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 1.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 1.0, 0.0 },
            .{ 0.0, 0.0, -5.0, 1.0 }, // Camera stays anchored here
        },
    };

    // 3. Projection Matrix: Vulkan clip space [0.0 to 1.0] Z depth
    const aspect: f32 = 800.0 / 600.0;
    const fov_scale: f32 = 1.0 / @tan(30.0 * (@as(f32, @floatCast(std.math.pi)) / 180.0));
    const near: f32 = 0.1;
    const far: f32 = 100.0;

    const proj = Mat4{ .data = .{
        .{ fov_scale / aspect, 0.0, 0.0, 0.0 },
        .{ 0.0, -fov_scale, 0.0, 0.0 },
        .{ 0.0, 0.0, far / (near - far), -1.0 },
        .{ 0.0, 0.0, (far * near) / (near - far), 0.0 },
    } };

    // 4. Matrix Multiplication: Proj * View * Model
    const mv = multiplyMatrices(view, model);
    return multiplyMatrices(proj, mv);
}

// C-compatible Column-Major Matrix Multiplication helper
fn multiplyMatrices(a: Mat4, b: Mat4) Mat4 {
    var out: Mat4 = undefined;
    inline for (0..4) |col| {
        inline for (0..4) |row| {
            var sum: f32 = 0.0;
            inline for (0..4) |k| {
                sum += a.data[k][row] * b.data[col][k];
            }
            out.data[col][row] = sum;
        }
    }
    return out;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDLInitFailed;
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Zig + SDL3 GPU Rotating Cube", 800, 600, 0) orelse return error.WindowCreationFailed;
    defer c.SDL_DestroyWindow(window);

    const gpu_device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, "vulkan") orelse return error.GPUDeviceCreationFailed;
    defer c.SDL_DestroyGPUDevice(gpu_device);

    if (!c.SDL_ClaimWindowForGPUDevice(gpu_device, window)) return error.ClaimWindowFailed;
    defer c.SDL_ReleaseWindowFromGPUDevice(gpu_device, window);

    const vert_shader = try loadShader(io, gpu_device, "shaders/cube.vert.spv", c.SDL_GPU_SHADERSTAGE_VERTEX);
    defer c.SDL_ReleaseGPUShader(gpu_device, vert_shader);

    const frag_shader = try loadShader(io, gpu_device, "shaders/cube.frag.spv", c.SDL_GPU_SHADERSTAGE_FRAGMENT);
    defer c.SDL_ReleaseGPUShader(gpu_device, frag_shader);

    // Geometry
    const vertices = [_]Vertex{
        .{ .pos = .{ -0.5, -0.5, 0.5 }, .color = .{ 1.0, 0.0, 0.0 } },
        .{ .pos = .{ 0.5, -0.5, 0.5 }, .color = .{ 0.0, 1.0, 0.0 } },
        .{ .pos = .{ 0.5, 0.5, 0.5 }, .color = .{ 0.0, 0.0, 1.0 } },
        .{ .pos = .{ -0.5, 0.5, 0.5 }, .color = .{ 1.0, 1.0, 0.0 } },
        .{ .pos = .{ -0.5, -0.5, -0.5 }, .color = .{ 1.0, 0.0, 1.0 } },
        .{ .pos = .{ 0.5, -0.5, -0.5 }, .color = .{ 0.0, 1.0, 1.0 } },
        .{ .pos = .{ 0.5, 0.5, -0.5 }, .color = .{ 1.0, 1.0, 1.0 } },
        .{ .pos = .{ -0.5, 0.5, -0.5 }, .color = .{ 0.0, 0.0, 0.0 } },
    };

    const indices = [_]u16{
        0, 1, 2, 2, 3, 0, // front
        1, 5, 6, 6, 2, 1, // right
        7, 6, 5, 5, 4, 7, // back
        4, 0, 3, 3, 7, 4, // left
        4, 5, 1, 1, 0, 4, // bottom
        3, 2, 6, 6, 7, 3, // top
    };

    // Create GPU buffers
    var vbuf_info = std.mem.zeroes(c.SDL_GPUBufferCreateInfo);
    vbuf_info.usage = c.SDL_GPU_BUFFERUSAGE_VERTEX;
    vbuf_info.size = @sizeOf(@TypeOf(vertices));
    const vertex_buffer = c.SDL_CreateGPUBuffer(gpu_device, &vbuf_info) orelse return error.BufferCreationFailed;
    defer c.SDL_ReleaseGPUBuffer(gpu_device, vertex_buffer);

    var ibuf_info = std.mem.zeroes(c.SDL_GPUBufferCreateInfo);
    ibuf_info.usage = c.SDL_GPU_BUFFERUSAGE_INDEX;
    ibuf_info.size = @sizeOf(@TypeOf(indices));
    const index_buffer = c.SDL_CreateGPUBuffer(gpu_device, &ibuf_info) orelse return error.BufferCreationFailed;
    defer c.SDL_ReleaseGPUBuffer(gpu_device, index_buffer);

    // === Upload data (very important!) ===
    {
        const cmd = c.SDL_AcquireGPUCommandBuffer(gpu_device) orelse return error.CommandBufferFailed;
        const copy_pass = c.SDL_BeginGPUCopyPass(cmd);

        // Upload vertices
        var tbuf_info = std.mem.zeroes(c.SDL_GPUTransferBufferCreateInfo);
        tbuf_info.usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
        tbuf_info.size = @sizeOf(@TypeOf(vertices));
        const vtx_transfer = c.SDL_CreateGPUTransferBuffer(gpu_device, &tbuf_info).?;
        {
            const ptr = c.SDL_MapGPUTransferBuffer(gpu_device, vtx_transfer, false);
            @memcpy(@as([*]u8, @ptrCast(ptr))[0..@sizeOf(@TypeOf(vertices))], std.mem.asBytes(&vertices));
            c.SDL_UnmapGPUTransferBuffer(gpu_device, vtx_transfer);
        }
        c.SDL_UploadToGPUBuffer(copy_pass, &.{ .transfer_buffer = vtx_transfer, .offset = 0 }, &.{ .buffer = vertex_buffer, .offset = 0, .size = @sizeOf(@TypeOf(vertices)) }, false);
        defer c.SDL_ReleaseGPUTransferBuffer(gpu_device, vtx_transfer);

        // Upload indices
        tbuf_info.size = @sizeOf(@TypeOf(indices));
        const idx_transfer = c.SDL_CreateGPUTransferBuffer(gpu_device, &tbuf_info).?;
        {
            const ptr = c.SDL_MapGPUTransferBuffer(gpu_device, idx_transfer, false);
            @memcpy(@as([*]u8, @ptrCast(ptr))[0..@sizeOf(@TypeOf(indices))], std.mem.asBytes(&indices));
            c.SDL_UnmapGPUTransferBuffer(gpu_device, idx_transfer);
        }
        c.SDL_UploadToGPUBuffer(copy_pass, &.{ .transfer_buffer = idx_transfer, .offset = 0 }, &.{ .buffer = index_buffer, .offset = 0, .size = @sizeOf(@TypeOf(indices)) }, false);
        defer c.SDL_ReleaseGPUTransferBuffer(gpu_device, idx_transfer);

        c.SDL_EndGPUCopyPass(copy_pass);
        _ = c.SDL_SubmitGPUCommandBuffer(cmd);
        // Small wait to ensure upload finishes
        try io.sleep(.fromMilliseconds(50), .awake);
    }

    // Pipeline
    var pipeline_info = std.mem.zeroes(c.SDL_GPUGraphicsPipelineCreateInfo);
    pipeline_info.vertex_shader = vert_shader;
    pipeline_info.fragment_shader = frag_shader;
    pipeline_info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;

    // Vertex input
    var binding = std.mem.zeroes(c.SDL_GPUVertexBufferDescription);
    binding.slot = 0;
    binding.pitch = @sizeOf(Vertex);
    binding.input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX;

    var attrs: [2]c.SDL_GPUVertexAttribute = .{
        std.mem.zeroes(c.SDL_GPUVertexAttribute),
        std.mem.zeroes(c.SDL_GPUVertexAttribute),
    };
    attrs[0].location = 0;
    attrs[0].buffer_slot = 0;
    attrs[0].format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3;
    attrs[0].offset = @offsetOf(Vertex, "pos");

    attrs[1].location = 1;
    attrs[1].buffer_slot = 0;
    attrs[1].format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3;
    attrs[1].offset = @offsetOf(Vertex, "color");

    pipeline_info.vertex_input_state.vertex_buffer_descriptions = &binding;
    pipeline_info.vertex_input_state.num_vertex_buffers = 1;
    pipeline_info.vertex_input_state.vertex_attributes = &attrs;
    pipeline_info.vertex_input_state.num_vertex_attributes = 2;

    // Color target
    var color_target = std.mem.zeroes(c.SDL_GPUColorTargetDescription);
    color_target.format = c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window);
    pipeline_info.target_info.color_target_descriptions = &color_target;
    pipeline_info.target_info.num_color_targets = 1;

    // Depth
    pipeline_info.target_info.has_depth_stencil_target = true;
    pipeline_info.target_info.depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM;
    pipeline_info.depth_stencil_state.enable_depth_test = true;
    pipeline_info.depth_stencil_state.enable_depth_write = true;
    pipeline_info.depth_stencil_state.compare_op = c.SDL_GPU_COMPAREOP_LESS;

    // Disable culling for testing
    pipeline_info.rasterizer_state.cull_mode = c.SDL_GPU_CULLMODE_NONE;

    const pipeline = c.SDL_CreateGPUGraphicsPipeline(gpu_device, &pipeline_info) orelse {
        std.log.err("Pipeline failed: {s}", .{c.SDL_GetError()});
        return error.PipelineFailed;
    };
    defer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, pipeline);

    // Depth texture
    var depth_info = std.mem.zeroes(c.SDL_GPUTextureCreateInfo);
    depth_info.type = c.SDL_GPU_TEXTURETYPE_2D;
    depth_info.format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM;
    depth_info.width = 800;
    depth_info.height = 600;
    depth_info.layer_count_or_depth = 1;
    depth_info.num_levels = 1;
    depth_info.usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET;
    const depth_tex = c.SDL_CreateGPUTexture(gpu_device, &depth_info) orelse return error.DepthTextureFailed;
    defer c.SDL_ReleaseGPUTexture(gpu_device, depth_tex);

    // Render loop
    var running = true;
    var event: c.SDL_Event = undefined;
    var angle: f32 = 0.0;

    // In your main loop initialization:
    var cube_x: f32 = 0.0;
    var cube_y: f32 = 0.0;
    const cube_z: f32 = 0.0; // 0.0 means it centers in front of the camera

    while (running) {
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT or
                (event.type == c.SDL_EVENT_KEY_DOWN and event.key.scancode == c.SDL_SCANCODE_ESCAPE))
            {
                running = false;
            }

            if (event.type == c.SDL_EVENT_KEY_DOWN) {
                switch (event.key.key) {
                    c.SDLK_LEFT => cube_x -= 0.1,
                    c.SDLK_RIGHT => cube_x += 0.1,
                    c.SDLK_UP => cube_y += 0.1, // Moves up
                    c.SDLK_DOWN => cube_y -= 0.1, // Moves down
                    else => {},
                }
            }
        }
        _ = c.SDL_WaitForGPUIdle(gpu_device);

        // angle += 0.8;
        angle += 0.1;

        const cmd = c.SDL_AcquireGPUCommandBuffer(gpu_device) orelse continue;
        var swapchain: ?*c.SDL_GPUTexture = null;
        if (!c.SDL_AcquireGPUSwapchainTexture(cmd, window, &swapchain, null, null)) {
            _ = c.SDL_SubmitGPUCommandBuffer(cmd);
            continue;
        }

        if (swapchain) |texture| {
            var color_target_info = std.mem.zeroes(c.SDL_GPUColorTargetInfo);
            color_target_info.texture = texture;
            color_target_info.clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.2, .a = 1.0 };
            color_target_info.load_op = c.SDL_GPU_LOADOP_CLEAR;

            var depth_target_info = std.mem.zeroes(c.SDL_GPUDepthStencilTargetInfo);
            depth_target_info.texture = depth_tex;
            depth_target_info.clear_depth = 1.0;
            depth_target_info.load_op = c.SDL_GPU_LOADOP_CLEAR;

            const render_pass = c.SDL_BeginGPURenderPass(cmd, &color_target_info, 1, &depth_target_info);
            c.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);

            // Bind buffers
            var vbind = c.SDL_GPUBufferBinding{ .buffer = vertex_buffer, .offset = 0 };
            c.SDL_BindGPUVertexBuffers(render_pass, 0, &vbind, 1);

            var ibind = c.SDL_GPUBufferBinding{ .buffer = index_buffer, .offset = 0 };
            c.SDL_BindGPUIndexBuffer(render_pass, &ibind, c.SDL_GPU_INDEXELEMENTSIZE_16BIT);

            // Push uniform
            // const mvp = createMVP(angle);
            const mvp = createMVP_Move(angle, cube_x, cube_y, cube_z);
            // const mvp = createMVP(angle, 0.0, 0.0, 5.0);
            c.SDL_PushGPUVertexUniformData(cmd, 0, &mvp, @sizeOf(@TypeOf(mvp)));

            c.SDL_DrawGPUIndexedPrimitives(render_pass, 36, 1, 0, 0, 0);

            c.SDL_EndGPURenderPass(render_pass);
        }
        _ = c.SDL_SubmitGPUCommandBuffer(cmd);
    }
}
