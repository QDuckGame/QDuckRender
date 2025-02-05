#ifndef UNIVERSAL_FORWARD_LIT_DEPTH_NORMALS_PASS_INCLUDED
#define UNIVERSAL_FORWARD_LIT_DEPTH_NORMALS_PASS_INCLUDED

#include "TerrainLitPasses.hlsl"

// DepthNormal pass
struct AttributesDepthNormal
{
    float4 positionOS : POSITION;
    half3 normalOS : NORMAL;
    float2 texcoord : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct VaryingsDepthNormal
{
    float4 uvMainAndLM             : TEXCOORD0; // xy: control, zw: lightmap
    half4 normal                   : TEXCOORD1;    // xyz: normal, w: viewDir.x
    half4 tangent                  : TEXCOORD2;    // xyz: tangent, w: viewDir.y
    half4 bitangent                : TEXCOORD3;    // xyz: bitangent, w: viewDir.z

    float4 clipPos                  : SV_POSITION;
    UNITY_VERTEX_OUTPUT_STEREO
};

VaryingsDepthNormal DepthNormalOnlyVertex(AttributesDepthNormal v)
{
    VaryingsDepthNormal o = (VaryingsDepthNormal)0;

    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    TerrainInstancing(v.positionOS, v.normalOS, v.texcoord);

    const VertexPositionInputs attributes = GetVertexPositionInputs(v.positionOS.xyz);

    o.uvMainAndLM.xy = v.texcoord;
    o.uvMainAndLM.zw = v.texcoord * unity_LightmapST.xy + unity_LightmapST.zw;

    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(attributes.positionWS);
    float4 vertexTangent = float4(cross(float3(0, 0, 1), v.normalOS), 1.0);
    VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, vertexTangent);

    o.normal = half4(normalInput.normalWS, viewDirWS.x);
    o.tangent = half4(normalInput.tangentWS, viewDirWS.y);
    o.bitangent = half4(normalInput.bitangentWS, viewDirWS.z);
    
    o.clipPos = attributes.positionCS;
    return o;
}

void DepthNormalOnlyFragment(
    VaryingsDepthNormal IN
    , out half4 outNormalWS : SV_Target0
#ifdef _WRITE_RENDERING_LAYERS
    , out float4 outRenderingLayers : SV_Target1
#endif
    )
{
    #ifdef _ALPHATEST_ON
        ClipHoles(IN.uvMainAndLM.xy);
    #endif

    //获取各个纹理层的属性
    SplatProps SplatProps1 = GetSplatProps2(IN.uvMainAndLM,0,_Splat0_ST);
    SplatProps SplatProps2 = GetSplatProps2(IN.uvMainAndLM,1,_Splat1_ST);
    SplatProps SplatProps3 = GetSplatProps2(IN.uvMainAndLM,2,_Splat2_ST);
    SplatProps SplatProps4 = GetSplatProps2(IN.uvMainAndLM,3,_Splat3_ST);
    SplatProps SplatProps5 = GetSplatProps2(IN.uvMainAndLM,4,_Splat4_ST);
    SplatProps SplatProps6 = GetSplatProps2(IN.uvMainAndLM,5,_Splat5_ST);
    //获取纹理信息
    float2 splatUV = (IN.uvMainAndLM.xy * (_Control_TexelSize.zw - 1.0f) + 0.5f) * _Control_TexelSize.xy;
    half4 splatControl = SAMPLE_TEXTURE2D(_Control, sampler_Control, splatUV);
    half4 splatControl1 = SAMPLE_TEXTURE2D(_Control1, sampler_Control1, splatUV);

    //获取各个纹理层的权重
    float control1 = splatControl.x * SplatProps1.height;float control2 = splatControl.y * SplatProps2.height;float control3 = splatControl.z * SplatProps3.height;
    float control4 = splatControl.w * SplatProps4.height;float control5 = splatControl1.x * SplatProps5.height;float control6 = splatControl1.y * SplatProps6.height;
    float weight_max = max(max(max(max(max(control1,control2),control3),control4),control5),control6);
    weight_max = weight_max - 0.1f;
    float weight1 = max(control1 - weight_max,0.0);
    float weight2 = max(control2 - weight_max,0.0);
    float weight3 = max(control3 - weight_max,0.0);
    float weight4 = max(control4 - weight_max,0.0);
    float weight5 = max(control5 - weight_max,0.0);
    float weight6 = max(control6 - weight_max,0.0);
    float weight_sum = weight1 + weight2 + weight3 + weight4 + weight5 + weight6;
    weight1 = weight1 / weight_sum;
    weight2 = weight2 / weight_sum;
    weight3 = weight3 / weight_sum;
    weight4 = weight4 / weight_sum;
    weight5 = weight5 / weight_sum;
    weight6 = weight6 / weight_sum;

    float3 mixNormal = SplatProps1.normal*weight1 + SplatProps2.normal*weight2 + SplatProps3.normal*weight3 + SplatProps4.normal*weight4 + SplatProps5.normal*weight5 + SplatProps6.normal*weight6;
    
    half3 viewDirWS = half3(IN.normal.w, IN.tangent.w, IN.bitangent.w);
    half3x3 tangentToWorld = half3x3(-IN.tangent.xyz, IN.bitangent.xyz, IN.normal.xyz);
    half3 normalWS = TransformTangentToWorld(mixNormal,tangentToWorld);
    
    normalWS = NormalizeNormalPerPixel(normalWS);

    outNormalWS = half4(normalWS, 0.0);

    #ifdef _WRITE_RENDERING_LAYERS
        uint renderingLayers = GetMeshRenderingLayer();
        outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
    #endif
}

#endif
