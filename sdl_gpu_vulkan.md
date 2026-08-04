


```zig
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

```


```
The -fov_scale in the second row of the projection matrix flips the Y axis back right-side up so Vulkan sees it correctly.
```

```
2. Standardized Column-Major Storage

Your original code was manually mixing row-major calculations, transposing them at the end, and then performing hardcoded array overrides. It is incredibly easy to accidentally scramble rows and columns this way.

- Old Code: Modifying final_mvp.data[3][2] after transposing changed the projection logic instead of changing the translation, which warped your cube into infinity.

- New Code: Uses native Column-Major mapping ([column][row]). In this format, column index 3 holds your exact spatial translation coordinates vector cleanly.
```

```
You noticed that const c crashed your build. This happened because your code or third-party wrappers likely imported C namespaces like this:

const c = @import("c"); // Imports SDL3 / Vulkan C bindings

```