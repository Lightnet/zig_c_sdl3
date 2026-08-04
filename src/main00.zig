const std = @import("std");
const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "");
    @cInclude("SDL3/SDL.h");
});

// Vertex structure matching our shader layout
const Vertex = struct {
    pos: [3]f32,
    color: [3]f32,
};

// Uniform Block for 3D Camera Math (Model-View-Projection)
const UniformBufferObject = struct {
    mvp: [4][4]f32,
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
    const file_size = stat.size;

    const allocator = std.heap.page_allocator;
    const code = try allocator.alloc(u8, file_size);
    defer allocator.free(code);

    _ = try file.readPositionalAll(io, code, 0);

    var info = std.mem.zeroes(c.SDL_GPUShaderCreateInfo);
    info.code_size = code.len;
    info.code = code.ptr;
    info.entrypoint = "main";
    info.format = c.SDL_GPU_SHADERFORMAT_SPIRV;
    info.stage = stage;

    // FIX: Explicitly notify SDL3 that the vertex shader has exactly 1 uniform block
    if (stage == c.SDL_GPU_SHADERSTAGE_VERTEX) {
        info.num_uniform_buffers = 1;
    } else {
        info.num_uniform_buffers = 0;
    }

    return c.SDL_CreateGPUShader(device, &info) orelse {
        std.log.err("Failed to create shader from {s}: {s}", .{ path, c.SDL_GetError() });
        return error.ShaderCreationFailed;
    };
}

// Simple identity / perspective / rotation matrix helper
fn createMVP(angle: f32) [4][4]f32 {
    const rad = angle * (std.math.pi / 180.0);
    const c_a = @cos(rad);
    const s_a = @sin(rad);

    // Combined Perspective * Translation * Y-Rotation matrix simplified
    // Standard aspect ratio 800/600 = 1.333, Near=0.1, Far=10.0
    // return .{
    //     .{ c_a * 1.35, 0.0, s_a, 0.0 },
    //     .{ 0.0, 1.8, 0.0, 0.0 },
    //     .{ -s_a * 1.0, 0.0, c_a * 1.0, 1.0 },
    //     .{ 0.0, 0.0, -2.5, 1.0 },
    // };

    return .{
        .{ c_a * 1.35, 0.0, s_a, 0.0 },
        .{ 0.0, 1.8, 0.0, 0.0 },
        .{ -s_a * 1.0, 0.0, c_a * 1.0, 1.0 },
        .{ 0.0, 0.0, -2.5, 5.0 },
    };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // --- Initialize SDL3 ---
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDLInitFailed;
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Zig 0.16.0 + SDL3 GPU 3D Cube", 800, 600, 0) orelse return error.WindowCreationFailed;
    defer c.SDL_DestroyWindow(window);

    const gpu_device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, "vulkan") orelse return error.GPUDeviceCreationFailed;
    defer c.SDL_DestroyGPUDevice(gpu_device);

    if (!c.SDL_ClaimWindowForGPUDevice(gpu_device, window)) return error.ClaimWindowFailed;
    defer c.SDL_ReleaseWindowFromGPUDevice(gpu_device, window);

    // --- Load 3D Shaders ---
    const vert_shader = try loadShader(io, gpu_device, "shaders/cube.vert.spv", c.SDL_GPU_SHADERSTAGE_VERTEX);
    defer c.SDL_ReleaseGPUShader(gpu_device, vert_shader);

    const frag_shader = try loadShader(io, gpu_device, "shaders/cube.frag.spv", c.SDL_GPU_SHADERSTAGE_FRAGMENT);
    defer c.SDL_ReleaseGPUShader(gpu_device, frag_shader);

    // --- Geometry Data (8 Corners, Unique Vertex Colors) ---
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

    // --- Index Data (Connect vertices to form 12 triangles / 6 faces) ---
    const indices = [_]u16{
        0, 1, 2, 2, 3, 0, // Front Face
        1, 5, 6, 6, 2, 1, // Right Face
        7, 6, 5, 5, 4, 7, // Back Face
        4, 0, 3, 3, 7, 4, // Left Face
        4, 5, 1, 1, 0, 4, // Bottom Face
        3, 2, 6, 6, 7, 3, // Top Face
    };

    // --- Allocate GPU Memory Buffers ---
    var v_buffer_desc = std.mem.zeroes(c.SDL_GPUBufferCreateInfo);
    v_buffer_desc.usage = c.SDL_GPU_BUFFERUSAGE_VERTEX;
    v_buffer_desc.size = @sizeOf(@TypeOf(vertices));
    const vertex_buffer = c.SDL_CreateGPUBuffer(gpu_device, &v_buffer_desc);
    defer c.SDL_ReleaseGPUBuffer(gpu_device, vertex_buffer);

    var i_buffer_desc = std.mem.zeroes(c.SDL_GPUBufferCreateInfo);
    i_buffer_desc.usage = c.SDL_GPU_BUFFERUSAGE_INDEX;
    i_buffer_desc.size = @sizeOf(@TypeOf(indices));
    const index_buffer = c.SDL_CreateGPUBuffer(gpu_device, &i_buffer_desc);
    defer c.SDL_ReleaseGPUBuffer(gpu_device, index_buffer);

    // NOTE: In production, issue a copy pass here via an SDL staging buffer
    // to map your local `vertices` and `indices` arrays into these GPU buffers.

    // --- Configure Graphics Pipeline States ---
    // --- Pipeline Creation ---
    var pipeline_info = std.mem.zeroes(c.SDL_GPUGraphicsPipelineCreateInfo);
    pipeline_info.vertex_shader = vert_shader;
    pipeline_info.fragment_shader = frag_shader;
    // pipeline_info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;

    // FIX: Inform the pipeline layout builder that 1 vertex uniform buffer block will be actively pushed
    // pipeline_info.num_vertex_uniform_buffers = 1;

    // FIX: Use SDL_GPUVertexBufferDescription instead of SDL_GPUVertexInputBindingDescription
    var vertex_binding = std.mem.zeroes(c.SDL_GPUVertexBufferDescription);
    vertex_binding.slot = 0;
    vertex_binding.input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX;
    vertex_binding.pitch = @sizeOf(Vertex); // FIX: SDL3 uses 'pitch' instead of 'stride'

    // FIX: Use SDL_GPUVertexAttribute instead of SDL_GPUVertexAttributeDescription
    var vertex_attrs = [_]c.SDL_GPUVertexAttribute{
        std.mem.zeroes(c.SDL_GPUVertexAttribute),
        std.mem.zeroes(c.SDL_GPUVertexAttribute),
    };

    // Attribute 0: Vec3 Position
    vertex_attrs[0].location = 0;
    vertex_attrs[0].buffer_slot = 0; // FIX: SDL3 uses 'buffer_slot' instead of 'binding'
    vertex_attrs[0].format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3;
    vertex_attrs[0].offset = @offsetOf(Vertex, "pos");

    // Attribute 1: Vec3 Colour
    vertex_attrs[1].location = 1;
    vertex_attrs[1].buffer_slot = 0; // FIX: SDL3 uses 'buffer_slot' instead of 'binding'
    vertex_attrs[1].format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3;
    vertex_attrs[1].offset = @offsetOf(Vertex, "color");

    // Assign corrected sub-structures back to your pipeline layout state
    pipeline_info.vertex_input_state.vertex_buffer_descriptions = &vertex_binding;
    pipeline_info.vertex_input_state.num_vertex_buffers = 1;
    pipeline_info.vertex_input_state.vertex_attributes = &vertex_attrs;
    pipeline_info.vertex_input_state.num_vertex_attributes = 2;

    // Output target setup
    var color_target_desc = std.mem.zeroes(c.SDL_GPUColorTargetDescription);
    color_target_desc.format = c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window);
    pipeline_info.target_info.color_target_descriptions = &color_target_desc;
    pipeline_info.target_info.num_color_targets = 1;

    // Add Depth sorting so back-faces do not render on top of front-faces
    pipeline_info.target_info.has_depth_stencil_target = true;
    pipeline_info.target_info.depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM;
    pipeline_info.depth_stencil_state.enable_depth_test = true;
    pipeline_info.depth_stencil_state.enable_depth_write = true;
    pipeline_info.depth_stencil_state.compare_op = c.SDL_GPU_COMPAREOP_LESS;

    const pipeline = c.SDL_CreateGPUGraphicsPipeline(gpu_device, &pipeline_info) orelse {
        std.log.err("Failed to create graphics pipeline: {s}", .{c.SDL_GetError()});
        return error.PipelineCreationFailed;
    };
    defer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, pipeline);

    // --- Allocate Depth Framebuffer Texture ---
    var depth_tex_desc = std.mem.zeroes(c.SDL_GPUTextureCreateInfo);
    depth_tex_desc.type = c.SDL_GPU_TEXTURETYPE_2D;
    depth_tex_desc.format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM;
    depth_tex_desc.width = 800;
    depth_tex_desc.height = 600;
    depth_tex_desc.layer_count_or_depth = 1;
    depth_tex_desc.num_levels = 1;
    depth_tex_desc.usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET;
    const depth_texture = c.SDL_CreateGPUTexture(gpu_device, &depth_tex_desc) orelse return error.DepthTextureCreationFailed;
    defer c.SDL_ReleaseGPUTexture(gpu_device, depth_texture);

    // --- Render Loop ---
    var running = true;
    var event: c.SDL_Event = undefined;
    var rotation_angle: f32 = 0.0;

    while (running) {
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) running = false;
            if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.scancode == c.SDL_SCANCODE_ESCAPE) running = false;
        }

        rotation_angle += 1.0; // Increment spin speed frame over frame

        const cmd_buffer = c.SDL_AcquireGPUCommandBuffer(gpu_device) orelse continue;

        // === UPLOAD VERTEX AND INDEX DATA ===
        const copy_pass = c.SDL_BeginGPUCopyPass(cmd_buffer); // Need a command buffer for upload

        // Vertex upload
        var transfer_buffer_desc = std.mem.zeroes(c.SDL_GPUTransferBufferCreateInfo);
        transfer_buffer_desc.usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
        transfer_buffer_desc.size = @sizeOf(@TypeOf(vertices));
        const vertex_transfer = c.SDL_CreateGPUTransferBuffer(gpu_device, &transfer_buffer_desc) orelse return error.TransferBufferFailed;
        defer c.SDL_ReleaseGPUTransferBuffer(gpu_device, vertex_transfer);

        {
            const mapped = c.SDL_MapGPUTransferBuffer(gpu_device, vertex_transfer, false);
            @memcpy(@as([*]u8, @ptrCast(mapped))[0..@sizeOf(@TypeOf(vertices))], std.mem.asBytes(&vertices));
            c.SDL_UnmapGPUTransferBuffer(gpu_device, vertex_transfer);
        }

        c.SDL_UploadToGPUBuffer(copy_pass, &c.SDL_GPUTransferBufferLocation{ .transfer_buffer = vertex_transfer, .offset = 0 }, &c.SDL_GPUBufferRegion{ .buffer = vertex_buffer, .offset = 0, .size = @sizeOf(@TypeOf(vertices)) }, false);

        // Index upload (same pattern)
        transfer_buffer_desc.size = @sizeOf(@TypeOf(indices));
        const index_transfer = c.SDL_CreateGPUTransferBuffer(gpu_device, &transfer_buffer_desc) orelse return error.TransferBufferFailed;
        defer c.SDL_ReleaseGPUTransferBuffer(gpu_device, index_transfer);

        {
            const mapped = c.SDL_MapGPUTransferBuffer(gpu_device, index_transfer, false);
            @memcpy(@as([*]u8, @ptrCast(mapped))[0..@sizeOf(@TypeOf(indices))], std.mem.asBytes(&indices));
            c.SDL_UnmapGPUTransferBuffer(gpu_device, index_transfer);
        }

        c.SDL_UploadToGPUBuffer(copy_pass, &c.SDL_GPUTransferBufferLocation{ .transfer_buffer = index_transfer, .offset = 0 }, &c.SDL_GPUBufferRegion{ .buffer = index_buffer, .offset = 0, .size = @sizeOf(@TypeOf(indices)) }, false);

        c.SDL_EndGPUCopyPass(copy_pass);
        _ = c.SDL_SubmitGPUCommandBuffer(cmd_buffer); // Submit the upload

        var swapchain_texture: ?*c.SDL_GPUTexture = null;
        if (!c.SDL_AcquireGPUSwapchainTexture(cmd_buffer, window, &swapchain_texture, null, null)) {
            _ = c.SDL_SubmitGPUCommandBuffer(cmd_buffer);
            continue;
        }

        if (swapchain_texture) |texture| {
            // Screen color attachment
            var color_target = std.mem.zeroes(c.SDL_GPUColorTargetInfo);
            color_target.texture = texture;
            color_target.clear_color = c.SDL_FColor{ .r = 0.1, .g = 0.15, .b = 0.25, .a = 1.0 };
            color_target.load_op = c.SDL_GPU_LOADOP_CLEAR;
            color_target.store_op = c.SDL_GPU_STOREOP_STORE;

            // Z-buffer depth attachment
            var depth_target = std.mem.zeroes(c.SDL_GPUDepthStencilTargetInfo);
            depth_target.texture = depth_texture;
            depth_target.clear_depth = 1.0;
            depth_target.load_op = c.SDL_GPU_LOADOP_CLEAR;
            depth_target.store_op = c.SDL_GPU_STOREOP_DONT_CARE;

            const render_pass = c.SDL_BeginGPURenderPass(cmd_buffer, &color_target, 1, &depth_target);
            c.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);

            // Bind Vertex Array Buffer
            var buf_binding = c.SDL_GPUBufferBinding{ .buffer = vertex_buffer, .offset = 0 };
            c.SDL_BindGPUVertexBuffers(render_pass, 0, &buf_binding, 1);

            // Bind Element Index Buffer
            var idx_binding = c.SDL_GPUBufferBinding{ .buffer = index_buffer, .offset = 0 };
            c.SDL_BindGPUIndexBuffer(render_pass, &idx_binding, c.SDL_GPU_INDEXELEMENTSIZE_16BIT);

            // Calculate active transformation and push directly to uniform memory block
            const mvp = createMVP(rotation_angle);
            c.SDL_PushGPUVertexUniformData(cmd_buffer, 0, &mvp, @sizeOf(@TypeOf(mvp)));

            // Draw index map: 36 units (6 faces * 2 tris per face * 3 indices per tri)
            c.SDL_DrawGPUIndexedPrimitives(render_pass, 36, 1, 0, 0, 0);

            c.SDL_EndGPURenderPass(render_pass);
        }
        _ = c.SDL_SubmitGPUCommandBuffer(cmd_buffer);
    }
}
