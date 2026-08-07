const std = @import("std");

pub const Vec3 = struct { x: f32, y: f32, z: f32 };
pub const Mat4 = struct {
    m: [4][4]f32,

    pub fn identity() Mat4 {
        var res = Mat4{ .m = std.mem.zeroes([4][4]f32) };
        res.m[0][0] = 1.0;
        res.m[1][1] = 1.0;
        res.m[2][2] = 1.0;
        res.m[3][3] = 1.0;
        return res;
    }

    // 1. Correct Translation Matrix (Row-Major format)
    pub fn translation(x: f32, y: f32, z: f32) Mat4 {
        var res = Mat4.identity();
        res.m[0][3] = x; // Row 0, Col 3
        res.m[1][3] = y; // Row 1, Col 3
        res.m[2][3] = z; // Row 2, Col 3
        return res;
    }

    // pub fn perspective(fovy_rad: f32, aspect: f32, near: f32, far: f32) Mat4 {
    //     var res = Mat4{ .m = std.mem.zeroes([4][4]f32) };
    //     const f = 1.0 / std.math.tan(fovy_rad / 2.0);
    //     res.m[0][0] = f / aspect;
    //     res.m[1][1] = f;
    //     res.m[2][2] = far / (near - far);
    //     res.m[2][3] = -1.0;
    //     res.m[3][2] = (near * far) / (near - far);
    //     return res;
    // }
    // pub fn perspective(fovy_rad: f32, aspect: f32, near: f32, far: f32) Mat4 {
    //     var res = Mat4{ .m = std.mem.zeroes([4][4]f32) };
    //     const f = 1.0 / std.math.tan(fovy_rad / 2.0);

    //     res.m[0][0] = f / aspect;
    //     res.m[1][1] = f;
    //     res.m[2][2] = (far + near) / (near - far);
    //     res.m[2][3] = -1.0;
    //     res.m[3][2] = (2.0 * far * near) / (near - far);
    //     // leave m[3][3] = 0
    //     return res;
    // }

    // pub fn perspective(fovy_rad: f32, aspect: f32, near: f32, far: f32) Mat4 {
    //     var res = Mat4{ .m = std.mem.zeroes([4][4]f32) };
    //     const f = 1.0 / std.math.tan(fovy_rad / 2.0);

    //     res.m[0][0] = f / aspect;
    //     res.m[1][1] = f;
    //     // DX12 depth [0, 1] range mapping:
    //     res.m[2][2] = far / (near - far);
    //     res.m[2][3] = -1.0; // Keeps it right-handed (looking down -Z)
    //     res.m[3][2] = (near * far) / (near - far);

    //     return res;
    // }

    // 2. Correct Perspective Matrix for Right-Handed, Row-Major, DX Depth [0, 1]
    pub fn perspective(fovy_rad: f32, aspect: f32, near: f32, far: f32) Mat4 {
        var res = Mat4{ .m = std.mem.zeroes([4][4]f32) };
        const f = 1.0 / std.math.tan(fovy_rad / 2.0);

        res.m[0][0] = f / aspect;
        res.m[1][1] = f;
        res.m[2][2] = far / (near - far);
        res.m[2][3] = (near * far) / (near - far); // Row 2, Col 3
        res.m[3][2] = -1.0; // Row 3, Col 2 (Puts W = -Z)
        return res;
    }

    pub fn rotate(angle_rad: f32, axis: Vec3) Mat4 {
        var res = Mat4.identity();
        const c = std.math.cos(angle_rad);
        const s = std.math.sin(angle_rad);
        const t = 1.0 - c;
        res.m[0][0] = t * axis.x * axis.x + c;
        res.m[0][1] = t * axis.x * axis.y - s * axis.z;
        res.m[0][2] = t * axis.x * axis.z + s * axis.y;
        res.m[1][0] = t * axis.x * axis.y + s * axis.z;
        res.m[1][1] = t * axis.y * axis.y + c;
        res.m[1][2] = t * axis.y * axis.z - s * axis.x;
        res.m[2][0] = t * axis.x * axis.z - s * axis.y;
        res.m[2][1] = t * axis.y * axis.z + s * axis.x;
        res.m[2][2] = t * axis.z * axis.z + c;
        return res;
    }

    pub fn multiply(a: Mat4, b: Mat4) Mat4 {
        var res = Mat4{ .m = std.mem.zeroes([4][4]f32) };
        for (0..4) |i| {
            for (0..4) |j| {
                for (0..4) |k| {
                    res.m[i][j] += a.m[i][k] * b.m[k][j];
                }
            }
        }
        return res;
    }

    pub fn transpose(self: Mat4) Mat4 {
        var res = Mat4{ .m = undefined };
        for (0..4) |i| {
            for (0..4) |j| {
                res.m[i][j] = self.m[j][i];
            }
        }
        return res;
    }
};
