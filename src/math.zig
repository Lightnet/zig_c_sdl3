const std = @import("std");

pub const Vec3 = struct { x: f32, y: f32, z: f32 };

pub const Mat4 = struct {
    // Changed from [4][4]f32 to a flat array of 16 floats
    m: [16]f32,

    pub fn identity() Mat4 {
        var res = Mat4{ .m = std.mem.zeroes([16]f32) };
        res.m[0] = 1.0; // [0 * 4 + 0]
        res.m[5] = 1.0; // [1 * 4 + 1]
        res.m[10] = 1.0; // [2 * 4 + 2]
        res.m[15] = 1.0; // [3 * 4 + 3]
        return res;
    }

    // 1. Correct Translation Matrix (Row-Major format flattened)
    pub fn translation(x: f32, y: f32, z: f32) Mat4 {
        var res = identity();
        // Last *row* for row-vector convention
        res.m[12] = x; // (3,0)
        res.m[13] = y; // (3,1)
        res.m[14] = z; // (3,2)
        // m[15] stays 1
        return res;
    }

    pub fn perspective(fovy_rad: f32, aspect: f32, near: f32, far: f32) Mat4 {
        var res = Mat4{ .m = std.mem.zeroes([16]f32) };
        const f = 1.0 / std.math.tan(fovy_rad * 0.5);

        res.m[0] = f / aspect; // (0,0)
        res.m[5] = f; // (1,1)
        res.m[10] = far / (near - far); // (2,2)
        res.m[11] = -1.0; // (2,3)  → produces w = -z
        res.m[14] = (near * far) / (near - far); // (3,2)
        // m[15] remains 0
        return res;
    }

    pub fn rotate(angle_rad: f32, axis: Vec3) Mat4 {
        // Normalize the axis (important!)
        const len = @sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z);
        const x = axis.x / len;
        const y = axis.y / len;
        const z = axis.z / len;

        const c = std.math.cos(angle_rad);
        const s = std.math.sin(angle_rad);
        const t = 1.0 - c;

        var res = identity();

        // Row 0
        res.m[0] = t * x * x + c;
        res.m[1] = t * x * y + s * z; // note the + for row-vector
        res.m[2] = t * x * z - s * y;

        // Row 1
        res.m[4] = t * x * y - s * z;
        res.m[5] = t * y * y + c;
        res.m[6] = t * y * z + s * x;

        // Row 2
        res.m[8] = t * x * z + s * y;
        res.m[9] = t * y * z - s * x;
        res.m[10] = t * z * z + c;

        // Last row stays 0 0 0 1 (identity already set it)
        return res;
    }

    pub fn multiply(a: Mat4, b: Mat4) Mat4 {
        var res = Mat4{ .m = std.mem.zeroes([16]f32) };
        for (0..4) |i| {
            for (0..4) |j| {
                for (0..4) |k| {
                    res.m[i * 4 + j] += a.m[i * 4 + k] * b.m[k * 4 + j];
                }
            }
        }
        return res;
    }

    pub fn transpose(self: Mat4) Mat4 {
        var res = Mat4{ .m = undefined };
        for (0..4) |i| {
            for (0..4) |j| {
                res.m[i * 4 + j] = self.m[j * 4 + i];
            }
        }
        return res;
    }
};
