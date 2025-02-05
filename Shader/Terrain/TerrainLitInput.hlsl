#ifndef CUSTOM_TERRAIN_LIT_INPUT_INCLUDED
#define CUSTOM_TERRAIN_LIT_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/DebugMipmapStreamingMacros.hlsl"

CBUFFER_START(UnityPerMaterial)
    float4 _MainTex_ST;
    half4 _BaseColor;
    half _Cutoff;

    half4 _Splat0_ST, _Splat1_ST, _Splat2_ST, _Splat3_ST, _Splat4_ST, _Splat5_ST;
    float4 _TerrainSize;

    UNITY_TEXTURE_STREAMING_DEBUG_VARS_FOR_TEX(_Control);
    UNITY_TEXTURE_STREAMING_DEBUG_VARS_FOR_TEX(_Control1);
 
CBUFFER_END

#define _Surface 0.0 // Terrain is always opaque

CBUFFER_START(_Terrain)
    float4 _Control_ST;
    float4 _Control_TexelSize;
    float4 _TerrainHeightmapRecipSize;   // float4(1.0f/width, 1.0f/height, 1.0f/(width-1), 1.0f/(height-1))
    float4 _TerrainHeightmapScale;       // float4(hmScale.x, hmScale.y / (float)(kMaxHeight), hmScale.z, 0.0f)
CBUFFER_END


TEXTURE2D(_Control);            SAMPLER(sampler_Control);
TEXTURE2D(_Control1);           SAMPLER(sampler_Control1);
TEXTURE2D_ARRAY(_SplatBaseMapArray); SAMPLER(sampler_SplatBaseMapArray);//
TEXTURE2D_ARRAY(_NormalMaskArray); SAMPLER(sampler_NormalMaskArray);


TEXTURE2D(_MainTex);       SAMPLER(sampler_MainTex);

#if defined(UNITY_INSTANCING_ENABLED) && defined(_TERRAIN_INSTANCED_PERPIXEL_NORMAL)
#define ENABLE_TERRAIN_PERPIXEL_NORMAL
#endif

#ifdef UNITY_INSTANCING_ENABLED
TEXTURE2D(_TerrainHeightmapTexture);
TEXTURE2D(_TerrainNormalmapTexture);
SAMPLER(sampler_TerrainNormalmapTexture);
#endif

UNITY_INSTANCING_BUFFER_START(Terrain)
UNITY_DEFINE_INSTANCED_PROP(float4, _TerrainPatchInstanceData)  // float4(xBase, yBase, skipScale, ~)
UNITY_INSTANCING_BUFFER_END(Terrain)

#ifdef _ALPHATEST_ON
TEXTURE2D(_TerrainHolesTexture);
SAMPLER(sampler_TerrainHolesTexture);

void ClipHoles(float2 uv)
{
    float hole = SAMPLE_TEXTURE2D(_TerrainHolesTexture, sampler_TerrainHolesTexture, uv).r;
    // Fixes bug where compression is enabled and 0 isn't actually 0 but low like 1/2047. (UUM-61913)
    float epsilon = 0.0005f;
    clip(hole < epsilon ? -1 : 1);
}
#endif

void TerrainInstancing(inout float4 positionOS, inout float3 normal, inout float2 uv)
{
#ifdef UNITY_INSTANCING_ENABLED
    float2 patchVertex = positionOS.xy;
    float4 instanceData = UNITY_ACCESS_INSTANCED_PROP(Terrain, _TerrainPatchInstanceData);

    float2 sampleCoords = (patchVertex.xy + instanceData.xy) * instanceData.z; // (xy + float2(xBase,yBase)) * skipScale
    float height = UnpackHeightmap(_TerrainHeightmapTexture.Load(int3(sampleCoords, 0)));

    positionOS.xz = sampleCoords * _TerrainHeightmapScale.xz;
    positionOS.y = height * _TerrainHeightmapScale.y;

#ifdef ENABLE_TERRAIN_PERPIXEL_NORMAL
    normal = float3(0, 1, 0);
#else
    normal = _TerrainNormalmapTexture.Load(int3(sampleCoords, 0)).rgb * 2 - 1;
#endif
    uv = sampleCoords * _TerrainHeightmapRecipSize.zw;
#endif
}

void TerrainInstancing(inout float4 positionOS, inout float3 normal)
{
    float2 uv = { 0, 0 };
    TerrainInstancing(positionOS, normal, uv);
}


#endif
