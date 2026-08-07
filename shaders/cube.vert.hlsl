struct VertexInput {
    // Location 0 -> POSITION maps to TEXCOORD0
    float3 position : TEXCOORD0; 
    // Location 1 -> COLOR maps to TEXCOORD1
    float4 color    : TEXCOORD1; 
};

struct VertexOutput {
    float4 position : SV_POSITION;
    float4 color    : COLOR;
};

cbuffer UniformData : register(b0, space1) {
    float4x4 mvp;
};

VertexOutput main(VertexInput input) {
    VertexOutput output;
    output.position = mul(mvp, float4(input.position, 1.0f));
    output.color = input.color;
    return output;
}
