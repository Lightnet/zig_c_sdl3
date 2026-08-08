// nope shader stuff error format or something...
const std = @import("std");
const math = @import("math.zig");

const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "1");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_gpu.h");
});

// Embed compiled DXIL binary byte arrays straight into the executable
const vs_dxil_bytes = @embedFile("cube.vert.dxil");
const ps_dxil_bytes = @embedFile("cube.frag.dxil");

const Vertex = extern struct {
    pos: [3]f32, // 12 bytes
    color: [4]f32, // 16 bytes
};

const UniformBlock = struct {
    // Maps perfectly to float mvp[16] in HLSL
    mvp: [16]f32,
};

// helper
// 1. The Helper Function
fn recreateDepthTexture(device: *c.SDL_GPUDevice, texture_ptr: *?*c.SDL_GPUTexture, w: u32, h: u32) void {
    // Release old texture if it exists using the pointer
    if (texture_ptr.*) |t| {
        c.SDL_ReleaseGPUTexture(device, t);
    }

    var format = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT;

    // Explicitly cast 'format' to match the expected parameter type (c_uint)
    if (!c.SDL_GPUTextureSupportsFormat(device, @intCast(format), // <-- Added type cast here
        c.SDL_GPU_TEXTURETYPE_2D, c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET))
    {
        format = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT;
    }

    const desc = c.SDL_GPUTextureCreateInfo{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = @intCast(format), // <-- Added type cast here as well
        .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        .width = w,
        .height = h,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
        .props = 0,
    };

    // Assign the new texture directly to the original variable
    texture_ptr.* = c.SDL_CreateGPUTexture(device, &desc);
}

pub fn main() !void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDLInitFailed;
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("SDL_GPU DX12 Cube", 800, 600, c.SDL_WINDOW_RESIZABLE) orelse return error.Win;
    defer c.SDL_DestroyWindow(window);

    // Enforce DXIL (DirectX 12) support on startup
    const gpu_device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_DXIL, true, null) orelse return error.GPU;
    defer c.SDL_DestroyGPUDevice(gpu_device);

    if (!c.SDL_ClaimWindowForGPUDevice(gpu_device, window)) return error.WindowClaim;
    defer c.SDL_ReleaseWindowFromGPUDevice(gpu_device, window);

    var depth_w: u32 = 800;
    var depth_h: u32 = 600;
    var depth_texture: ?*c.SDL_GPUTexture = null;

    // --- Geometry Data Definitions ---
    const vertices = [_]Vertex{
        .{ .pos = .{ -0.5, -0.5, 0.5 }, .color = .{ 1, 0, 0, 1 } },
        .{ .pos = .{ 0.5, -0.5, 0.5 }, .color = .{ 0, 1, 0, 1 } },
        .{ .pos = .{ 0.5, 0.5, 0.5 }, .color = .{ 0, 0, 1, 1 } },
        .{ .pos = .{ -0.5, 0.5, 0.5 }, .color = .{ 1, 1, 0, 1 } },
        .{ .pos = .{ -0.5, -0.5, -0.5 }, .color = .{ 1, 0, 1, 1 } },
        .{ .pos = .{ 0.5, -0.5, -0.5 }, .color = .{ 0, 1, 1, 1 } },
        .{ .pos = .{ 0.5, 0.5, -0.5 }, .color = .{ 1, 1, 1, 1 } },
        .{ .pos = .{ -0.5, 0.5, -0.5 }, .color = .{ 0, 0, 0, 1 } },
    };
    // const indices = [_]u16{
    //     0, 1, 2, 2, 3, 0, 1, 5, 6, 6, 2, 1,
    //     7, 6, 5, 5, 4, 7, 4, 0, 3, 3, 7, 4,
    //     4, 5, 1, 1, 0, 4, 3, 2, 6, 6, 7, 3,
    // };

    const indices = [_]u16{
        0, 1, 2, 2, 3, 0, // Front Face (CCW)
        1, 5, 6, 6, 2, 1, // Right Face (CCW)
        7, 6, 5, 5, 4, 7, // Back Face  (CCW)
        4, 0, 3, 3, 7, 4, // Left Face  (CCW)
        4, 5, 1, 1, 0, 4, // Bottom Face(CCW)
        3, 7, 6, 6, 2, 3, // Top Face   (Fixed to CCW, originally: 3, 2, 6, 6, 7, 3)
    };

    // --- GPU Buffer Creation ---
    const v_info = c.SDL_GPUBufferCreateInfo{ .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = @sizeOf(@TypeOf(vertices)) };
    const i_info = c.SDL_GPUBufferCreateInfo{ .usage = c.SDL_GPU_BUFFERUSAGE_INDEX, .size = @sizeOf(@TypeOf(indices)) };

    const vertex_buf = c.SDL_CreateGPUBuffer(gpu_device, &v_info) orelse return error.Buf;
    const index_buf = c.SDL_CreateGPUBuffer(gpu_device, &i_info) orelse return error.Buf;
    defer c.SDL_ReleaseGPUBuffer(gpu_device, vertex_buf);
    defer c.SDL_ReleaseGPUBuffer(gpu_device, index_buf);

    // --- Data Upload via Staging Transfers ---
    const stg_info = c.SDL_GPUTransferBufferCreateInfo{ .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = v_info.size + i_info.size };
    const staging_buf = c.SDL_CreateGPUTransferBuffer(gpu_device, &stg_info) orelse return error.Stg;
    defer c.SDL_ReleaseGPUTransferBuffer(gpu_device, staging_buf);

    const data_ptr = c.SDL_MapGPUTransferBuffer(gpu_device, staging_buf, false) orelse return error.Map;
    @memcpy(@as([*]u8, @ptrCast(data_ptr))[0..v_info.size], std.mem.asBytes(&vertices));
    @memcpy(@as([*]u8, @ptrCast(data_ptr))[v_info.size .. v_info.size + i_info.size], std.mem.asBytes(&indices));
    c.SDL_UnmapGPUTransferBuffer(gpu_device, staging_buf);

    const upload_cmd = c.SDL_AcquireGPUCommandBuffer(gpu_device) orelse return error.Cmd;
    const copy_pass = c.SDL_BeginGPUCopyPass(upload_cmd) orelse return error.Copy;

    const v_loc = c.SDL_GPUTransferBufferLocation{ .transfer_buffer = staging_buf, .offset = 0 };
    const v_rgn = c.SDL_GPUBufferRegion{ .buffer = vertex_buf, .offset = 0, .size = v_info.size };
    c.SDL_UploadToGPUBuffer(copy_pass, &v_loc, &v_rgn, false);

    const i_loc = c.SDL_GPUTransferBufferLocation{ .transfer_buffer = staging_buf, .offset = v_info.size };
    const i_rgn = c.SDL_GPUBufferRegion{ .buffer = index_buf, .offset = 0, .size = i_info.size };
    c.SDL_UploadToGPUBuffer(copy_pass, &i_loc, &i_rgn, false);

    c.SDL_EndGPUCopyPass(copy_pass);
    _ = c.SDL_SubmitGPUCommandBuffer(upload_cmd);

    std.log.info("VS DXIL size = {}, PS DXIL size = {}", .{ vs_dxil_bytes.len, ps_dxil_bytes.len });
    std.log.info("Vertex Struct Size Check: {}", .{@sizeOf(Vertex)});

    // --- Create Shaders from Precompiled Bytecode ---
    const vs_create_info = c.SDL_GPUShaderCreateInfo{
        .code = vs_dxil_bytes.ptr,
        .code_size = vs_dxil_bytes.len,
        .entrypoint = "main",
        .format = c.SDL_GPU_SHADERFORMAT_DXIL,
        .stage = c.SDL_GPU_SHADERSTAGE_VERTEX,
        .num_samplers = 0,
        .num_storage_textures = 0,
        .num_storage_buffers = 0,
        .num_uniform_buffers = 1, // Correct: Vertex shader uses cbuffer b0
    };
    const vertex_shader = c.SDL_CreateGPUShader(gpu_device, &vs_create_info) orelse return error.ShaderCreation;
    defer c.SDL_ReleaseGPUShader(gpu_device, vertex_shader);

    const ps_create_info = c.SDL_GPUShaderCreateInfo{
        .code = ps_dxil_bytes.ptr,
        .code_size = ps_dxil_bytes.len,
        .entrypoint = "main",
        .format = c.SDL_GPU_SHADERFORMAT_DXIL,
        .stage = c.SDL_GPU_SHADERSTAGE_FRAGMENT,
        .num_samplers = 0,
        .num_storage_textures = 0,
        .num_storage_buffers = 0,
        .num_uniform_buffers = 0, // FIXED: Pixel shader does not use cbuffers!
    };
    const pixel_shader = c.SDL_CreateGPUShader(gpu_device, &ps_create_info) orelse return error.ShaderCreation;
    defer c.SDL_ReleaseGPUShader(gpu_device, pixel_shader);

    // --- Pipeline Configurations ---

    // 1. Rename arrays to unique constants to guarantee stable stack memory addresses
    const bind_desc = [_]c.SDL_GPUVertexBufferDescription{
        .{
            .slot = 0,
            .pitch = @sizeOf(Vertex),
            .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
        },
    };

    const attr_desc = [_]c.SDL_GPUVertexAttribute{
        .{ .location = 0, .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(Vertex, "pos") },
        .{ .location = 1, .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = @offsetOf(Vertex, "color") },
    };

    // 2. Build the color target descriptor cleanly
    var color_target_desc = std.mem.zeroes(c.SDL_GPUColorTargetDescription);
    color_target_desc.format = c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window);
    color_target_desc.blend_state = .{
        .src_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
        .dst_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ZERO,
        .color_blend_op = c.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ZERO,
        .alpha_blend_op = c.SDL_GPU_BLENDOP_ADD,
        .color_write_mask = 0xF, // All channels (RGBA)
        .enable_blend = false,
    };

    // 3. Build the target info payload using a guaranteed local variable assignment
    const target_info = c.SDL_GPUGraphicsPipelineTargetInfo{
        .color_target_descriptions = &color_target_desc,
        .num_color_targets = 1,
        .has_depth_stencil_target = true,
        // .depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_INVALID,
        .depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT, // depth format
    };

    // 4. Instantiate the final creation description using clean structural literals.
    // Do NOT use std.mem.zeroes for the top level here; declare the fields explicitly
    // so the compiler accurately retains the pinned memory pointers.
    const pip_info = c.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = pixel_shader,
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &bind_desc, // Points to fixed stack memory
            .num_vertex_buffers = 1,
            .vertex_attributes = &attr_desc, // Points to fixed stack memory
            .num_vertex_attributes = 2,
        },
        .rasterizer_state = .{
            .fill_mode = c.SDL_GPU_FILLMODE_FILL,
            .cull_mode = c.SDL_GPU_CULLMODE_NONE,
            .front_face = c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
            .enable_depth_clip = true,
        },
        .multisample_state = .{
            .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
            .sample_mask = 0, // Enforced validation check fixed
            .enable_mask = false,
        },
        .depth_stencil_state = .{
            // .compare_op = c.SDL_GPU_COMPAREOP_ALWAYS, // nope
            .compare_op = c.SDL_GPU_COMPAREOP_LESS, // or LESS_OR_EQUAL
            .back_stencil_state = std.mem.zeroes(c.SDL_GPUStencilOpState),
            .front_stencil_state = std.mem.zeroes(c.SDL_GPUStencilOpState),
            .compare_mask = 0,
            .write_mask = 0,
            // .enable_depth_test = false,
            // .enable_depth_write = false,
            .enable_depth_test = true, // Set to true
            .enable_depth_write = true, // Set to true
            .enable_stencil_test = false,
            .padding1 = 0,
            .padding2 = 0,
            .padding3 = 0,
        },
        .target_info = target_info,
        .props = 0,
    };

    const depth_texture_desc = c.SDL_GPUTextureCreateInfo{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
        .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        .width = @intCast(800),
        .height = @intCast(600),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
        .props = 0,
    };
    depth_h = 600;
    depth_w = 800;
    //create texture depth for resize later if event trigger
    depth_texture = c.SDL_CreateGPUTexture(gpu_device, &depth_texture_desc) orelse {
        std.log.err("Failed to create depth texture: {s}", .{c.SDL_GetError()});
        return error.DepthTextureCreationFailed;
    };
    // Clean it up at the very end of your program (where you release vertex_buf)
    defer c.SDL_ReleaseGPUTexture(gpu_device, depth_texture); // when shutting down!

    // 5. Fire off the creation call
    const pipeline = c.SDL_CreateGPUGraphicsPipeline(gpu_device, &pip_info) orelse {
        std.log.err("Pipeline failed: {s}", .{c.SDL_GetError()});
        std.log.err("Swapchain format = {}", .{color_target_desc.format});
        return error.PipelineCreationFailed;
    };
    defer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, pipeline);

    var quit = false;
    var time_ticks: f32 = 0.0;

    // --- Main Loop ---
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) quit = true;

            if (event.type == c.SDL_EVENT_WINDOW_RESIZED) {
                depth_w = @intCast(event.window.data1);
                depth_h = @intCast(event.window.data2);

                std.log.debug("RESIZE {}x{}", .{ depth_w, depth_h });

                recreateDepthTexture(gpu_device, &depth_texture, depth_w, depth_h);
            }
        }

        // time_ticks += 0.015;
        time_ticks += 0.0001;

        //const model = math.Mat4.identity();
        const model = math.Mat4.rotate(time_ticks, .{ .x = 0.5, .y = 1.0, .z = 0.0 });

        const view = math.Mat4.translation(0.0, 0.0, -5.0); // now uses m[12..14]
        const proj = math.Mat4.perspective(45.0 * (std.math.pi / 180.0), 800.0 / 600.0, 0.1, 100.0);

        const mv = math.Mat4.multiply(model, view);
        const mvp = math.Mat4.multiply(mv, proj);

        const uniforms = UniformBlock{ .mvp = mvp.m };

        //---------------------------------------
        const render_cmd = c.SDL_AcquireGPUCommandBuffer(gpu_device) orelse continue;

        var swap_tex: ?*c.SDL_GPUTexture = null;
        if (!c.SDL_AcquireGPUSwapchainTexture(render_cmd, window, &swap_tex, null, null)) {
            _ = c.SDL_SubmitGPUCommandBuffer(render_cmd);
            continue;
        }

        if (swap_tex) |tex| {
            // FIX: Assign to the .format field, not the whole struct
            color_target_desc.format = c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window);
            color_target_desc.blend_state = std.mem.zeroes(c.SDL_GPUColorTargetBlendState); // default opaque
            // const pipeline = c.SDL_CreateGPUGraphicsPipeline(gpu_device, &pip_info) orelse {
            //     _ = c.SDL_SubmitGPUCommandBuffer(render_cmd);
            //     continue;
            // };
            // defer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, pipeline);

            var color_target = c.SDL_GPUColorTargetInfo{ .texture = tex, .clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 }, .load_op = c.SDL_GPU_LOADOP_CLEAR, .store_op = c.SDL_GPU_STOREOP_STORE };

            // --- PLACE THIS DEPTH TARGET CONFIGURATION HERE ---
            var depth_target = c.SDL_GPUDepthStencilTargetInfo{
                .texture = depth_texture, // Points to the texture created in init
                .clear_depth = 1.0, // Clears depth buffer to furthest distance
                .load_op = c.SDL_GPU_LOADOP_CLEAR, // Force clear every frame
                .store_op = c.SDL_GPU_STOREOP_DONT_CARE,
                .stencil_load_op = c.SDL_GPU_LOADOP_DONT_CARE,
                .stencil_store_op = c.SDL_GPU_STOREOP_DONT_CARE,
                .clear_stencil = 0,
                .cycle = false, // Set to true if updating depth texture data while in-flight, otherwise false
                // .padding1 = 0,
                // .padding2 = 0,
            };

            // const render_pass = c.SDL_BeginGPURenderPass(render_cmd, &color_target, 1, null) orelse {
            //     _ = c.SDL_SubmitGPUCommandBuffer(render_cmd);
            //     continue;
            // };

            // --- UPDATE THIS CALL: Pass &depth_target instead of null ---
            const render_pass = c.SDL_BeginGPURenderPass(render_cmd, &color_target, 1, &depth_target) orelse {
                _ = c.SDL_SubmitGPUCommandBuffer(render_cmd);
                continue;
            };

            c.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);

            const v_binding = c.SDL_GPUBufferBinding{ .buffer = vertex_buf, .offset = 0 };
            c.SDL_BindGPUVertexBuffers(render_pass, 0, &v_binding, 1);

            const i_binding = c.SDL_GPUBufferBinding{ .buffer = index_buf, .offset = 0 };
            c.SDL_BindGPUIndexBuffer(render_pass, &i_binding, c.SDL_GPU_INDEXELEMENTSIZE_16BIT);

            c.SDL_PushGPUVertexUniformData(render_cmd, 0, &uniforms, @sizeOf(UniformBlock));
            c.SDL_DrawGPUIndexedPrimitives(render_pass, 36, 1, 0, 0, 0);

            c.SDL_EndGPURenderPass(render_pass);
        }
        _ = c.SDL_SubmitGPUCommandBuffer(render_cmd);
    }
}
