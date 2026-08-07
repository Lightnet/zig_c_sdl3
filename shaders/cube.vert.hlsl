struct VertexInput {
    float3 position : TEXCOORD0; 
    float4 color    : TEXCOORD1; 
};

struct VertexOutput {
    float4 position : SV_POSITION;
    float4 color    : COLOR;
};

cbuffer UniformData : register(b0, space1) {
    // Telling HLSL exactly how the Zig array is laid out in memory
    row_major float4x4 mvp; 
};

VertexOutput main(VertexInput input) {
    VertexOutput output;
    
    // Multiply vector by matrix (Row-Vector * Row-Major Matrix)
    output.position = mul(float4(input.position, 1.0f), mvp);
    output.color = input.color;
    
    return output;
}
