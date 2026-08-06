#version 450

layout(location = 0) in vec3 inColor;
layout(location = 1) in vec2 inUV;

layout(location = 0) out vec4 fragColor;

layout(set = 2, binding = 0) uniform sampler2D texSampler;

void main() {
    fragColor = texture(texSampler, inUV);
    // Optional: multiply by vertex color
    // fragColor = texture(texSampler, inUV) * vec4(inColor, 1.0);
}