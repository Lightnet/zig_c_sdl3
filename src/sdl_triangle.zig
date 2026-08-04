const std = @import("std");

const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "");
    @cInclude("SDL3/SDL.h");
});

fn loadShader(
    io: std.Io,
    device: *c.SDL_GPUDevice,
    path: []const u8,
    stage: c.SDL_GPUShaderStage,
) !*c.SDL_GPUShader {
    const cwd = std.Io.Dir.cwd();
    var file = try cwd.openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);

    // FIX: Use .stat(io) to get file metrics in Zig 0.16.0
    const stat = try file.stat(io);
    const file_size = stat.size;

    // Allocate exactly enough memory for our SPIR-V bytecode
    const allocator = std.heap.page_allocator;
    const code = try allocator.alloc(u8, file_size);
    defer allocator.free(code);

    // FIX: Pass 'code' buffer first, then the file read offset (0)
    _ = try file.readPositionalAll(io, code, 0);

    // Populate SDL3 GPU Shader Creation Info
    var info = std.mem.zeroes(c.SDL_GPUShaderCreateInfo);
    info.code_size = code.len;
    info.code = code.ptr;
    info.entrypoint = "main";
    info.format = c.SDL_GPU_SHADERFORMAT_SPIRV;
    info.stage = stage;

    return c.SDL_CreateGPUShader(device, &info) orelse {
        std.log.err("Failed to create shader from {s}: {s}", .{ path, c.SDL_GetError() });
        return error.ShaderCreationFailed;
    };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io; // Extract the modern 0.16.0 IO handle

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDLInitFailed;
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Zig 0.16.0 + SDL3 GPU Triangle", 800, 600, 0) orelse return error.WindowCreationFailed;
    defer c.SDL_DestroyWindow(window);

    const gpu_device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, "vulkan") orelse return error.GPUDeviceCreationFailed;
    defer c.SDL_DestroyGPUDevice(gpu_device);

    if (!c.SDL_ClaimWindowForGPUDevice(gpu_device, window)) return error.ClaimWindowFailed;
    defer c.SDL_ReleaseWindowFromGPUDevice(gpu_device, window);

    // --- Shader Loading (Updated to pass the io context) ---
    const vert_shader = try loadShader(io, gpu_device, "shaders/triangle.vert.spv", c.SDL_GPU_SHADERSTAGE_VERTEX);
    defer c.SDL_ReleaseGPUShader(gpu_device, vert_shader);

    const frag_shader = try loadShader(io, gpu_device, "shaders/triangle.frag.spv", c.SDL_GPU_SHADERSTAGE_FRAGMENT);
    defer c.SDL_ReleaseGPUShader(gpu_device, frag_shader);

    // --- Pipeline Creation ---
    var pipeline_info = std.mem.zeroes(c.SDL_GPUGraphicsPipelineCreateInfo);

    // Attach Shaders
    pipeline_info.vertex_shader = vert_shader;
    pipeline_info.fragment_shader = frag_shader;

    // Primitive type (Triangle List)
    pipeline_info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;

    // Color Target Format (Must match the swapchain format)
    var color_target_desc = std.mem.zeroes(c.SDL_GPUColorTargetDescription);
    color_target_desc.format = c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window);

    pipeline_info.target_info.color_target_descriptions = &color_target_desc;
    pipeline_info.target_info.num_color_targets = 1;

    const pipeline = c.SDL_CreateGPUGraphicsPipeline(gpu_device, &pipeline_info) orelse {
        std.log.err("Failed to create graphics pipeline: {s}", .{c.SDL_GetError()});
        return error.PipelineCreationFailed;
    };
    defer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, pipeline);

    var running = true;
    var event: c.SDL_Event = undefined;

    while (running) {
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) running = false;
            if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.scancode == c.SDL_SCANCODE_ESCAPE) running = false;
        }

        const cmd_buffer = c.SDL_AcquireGPUCommandBuffer(gpu_device) orelse continue;

        var swapchain_texture: ?*c.SDL_GPUTexture = null;
        if (!c.SDL_AcquireGPUSwapchainTexture(cmd_buffer, window, &swapchain_texture, null, null)) {
            _ = c.SDL_SubmitGPUCommandBuffer(cmd_buffer);
            continue;
        }

        if (swapchain_texture) |texture| {
            var color_target = std.mem.zeroes(c.SDL_GPUColorTargetInfo);
            color_target.texture = texture;
            color_target.clear_color = c.SDL_FColor{ .r = 0.1, .g = 0.15, .b = 0.25, .a = 1.0 };
            color_target.load_op = c.SDL_GPU_LOADOP_CLEAR;
            color_target.store_op = c.SDL_GPU_STOREOP_STORE;

            const render_pass = c.SDL_BeginGPURenderPass(cmd_buffer, &color_target, 1, null);

            // Bind our Vulkan-baked pipeline
            c.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);

            // Draw 3 vertices, 1 instance (hardcoded positions inside the shader)
            c.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0);

            c.SDL_EndGPURenderPass(render_pass);
        }

        _ = c.SDL_SubmitGPUCommandBuffer(cmd_buffer);
    }
}
