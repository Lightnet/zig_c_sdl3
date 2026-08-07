# zig_c_sdl3

# License: MIT

# Libraries:
- SDL 3.4.12
- ziglua#d59103e257b25ae892cdede9a671366e8d4f3e51

# Zig:
- 0.16.0

# Information:
  This sample project test for Zig 0.16.0, SDL 3.4.12 and other libs to check.

  To test vulkan set up in gpu api SDL 3.

# Examples:
- triangle 2d
- cube color
- cube texture for png
- sdl window frame test
- sdl debug text test

# shader.bat:
```
@echo off

set "PATH=%PATH%;x:\VulkanSDK\1.4.313.0\Bin"

@REM glslc shaders/triangle.vert -o shaders/triangle.vert.spv
@REM glslc shaders/triangle.frag -o shaders/triangle.frag.spv

glslc shaders/cube.vert -o shaders/cube.vert.spv
glslc shaders/cube.frag -o shaders/cube.frag.spv
```
 - compile shaders

# dx12
```
# Compile Vertex Shader (-T vs_6_0 means Vertex Shader model 6.0)
dxc -T vs_6_0 -E VSMain shaders/shaders.hlsl -Fo src/vs.dxil

# Compile Pixel/Fragment Shader (-T ps_6_0 means Pixel Shader model 6.0)
dxc -T ps_6_0 -E PSMain shaders/shaders.hlsl -Fo src/ps.dxil
```

## tests
```
dxc -T vs_6_0 -E VSMain -Fo src/vs.dxil shaders/shaders.hlsl
dxc -T ps_6_0 -E PSMain -Fo src/ps.dxil shaders/shaders.hlsl
```

```
dxc -T vs_6_0 -E main -Fo build/cube.vert.dxil shaders/cube.vert.hlsl
dxc -T ps_6_0 -E main -Fo build/cube.frag.dxil shaders/cube.frag.hlsl
```


# Repo:
```
zig fetch --save=sdl https://github.com/libsdl-org/SDL/releases/download/release-3.4.12/SDL3-devel-3.4.12-mingw.zip
```
- Download dll for library without need to compile SDL 3 dll.

# ziglua:
- might not work 0.16.0 
```
zig fetch --save git+https://github.com/natecraddock/ziglua
```
```
zig fetch --save git+https://github.com/natecraddock/ziglua#0.6.0
```

```
.url = "git+https://github.com/natecraddock/ziglua#d59103e257b25ae892cdede9a671366e8d4f3e51",
```
-  Last stable build for zig 0.16.0