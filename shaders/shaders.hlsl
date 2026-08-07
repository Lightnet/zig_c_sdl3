struct VSInput {
    // Explicitly string-match the TEXCOORD slots to map to location 0 and 1
    float3 pos   : TEXCOORD0; 
    float4 color : TEXCOORD1;    
};

struct VSOutput {
    float4 pos   : SV_POSITION;
    float4 color : COLOR0;    
};

// Uniform Block for Model-View-Projection Matrix
cbuffer Uniforms : register(b0, space0) {
    float4x4 mvp;
};

VSOutput VSMain(VSInput input) {
    VSOutput output;
    // Row/Column major depends on your math.zig. If your cube is skewed, flip the mul() ordering!
    output.pos = mul(mvp, float4(input.pos, 1.0));
    output.color = input.color;
    return output;
}

float4 PSMain(VSOutput input) : SV_Target {
    return input.color;
}
