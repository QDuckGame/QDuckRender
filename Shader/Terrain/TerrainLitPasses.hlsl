
#ifndef UNIVERSAL_TERRAIN_LIT_PASSES_INCLUDED
#define UNIVERSAL_TERRAIN_LIT_PASSES_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "../CustomLighting.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float2 texcoord : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 uvMainAndLM              : TEXCOORD0; // xy: control, zw: lightmap
    #if defined(_NORMALMAP) && !defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
    half4 normal                    : TEXCOORD1;    // xyz: normal, w: viewDir.x
    half4 tangent                   : TEXCOORD2;    // xyz: tangent, w: viewDir.y
    half4 bitangent                 : TEXCOORD3;    // xyz: bitangent, w: viewDir.z
    #else
    half3 normal                    : TEXCOORD1;
    half3 vertexSH                  : TEXCOORD2; // SH
    #endif
    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        half4 fogFactorAndVertexLight   : TEXCOORD4; // x: fogFactor, yzw: vertex light
    #else
        half  fogFactor                 : TEXCOORD5;
    #endif
    float3 positionWS               : TEXCOORD6;
#if defined(DYNAMICLIGHTMAP_ON)
    float2 dynamicLightmapUV        : TEXCOORD7;
#endif
#ifdef USE_APV_PROBE_OCCLUSION
    float4 probeOcclusion           : TEXCOORD8;
#endif

    float4 clipPos                  : SV_POSITION;
    UNITY_VERTEX_OUTPUT_STEREO
};

void InitializeInputData(Varyings IN, half3 normalTS, out InputData inputData)
{
    inputData = (InputData)0;

    inputData.positionWS = IN.positionWS;
    inputData.positionCS = IN.clipPos;

    #if defined(_NORMALMAP) && !defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
        half3 viewDirWS = half3(IN.normal.w, IN.tangent.w, IN.bitangent.w);
        inputData.tangentToWorld = half3x3(-IN.tangent.xyz, IN.bitangent.xyz, IN.normal.xyz);
        inputData.normalWS = TransformTangentToWorld(normalTS, inputData.tangentToWorld);
        half3 SH = 0;
    #elif defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
        half3 viewDirWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
        float2 sampleCoords = (IN.uvMainAndLM.xy / _TerrainHeightmapRecipSize.zw + 0.5f) * _TerrainHeightmapRecipSize.xy;
        half3 normalWS = TransformObjectToWorldNormal(normalize(SAMPLE_TEXTURE2D(_TerrainNormalmapTexture, sampler_TerrainNormalmapTexture, sampleCoords).rgb * 2 - 1));
        half3 tangentWS = cross(GetObjectToWorldMatrix()._13_23_33, normalWS);
        inputData.normalWS = TransformTangentToWorld(normalTS, half3x3(-tangentWS, cross(normalWS, tangentWS), normalWS));
        half3 SH = IN.vertexSH;
    #else
        half3 viewDirWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
        inputData.normalWS = IN.normal;
        half3 SH = IN.vertexSH;
    #endif

    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    inputData.viewDirectionWS = viewDirWS;
    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        inputData.fogCoord = InitializeInputDataFog(float4(IN.positionWS, 1.0), IN.fogFactorAndVertexLight.x);
        inputData.vertexLighting = IN.fogFactorAndVertexLight.yzw;
    #else
    inputData.fogCoord = InitializeInputDataFog(float4(IN.positionWS, 1.0), IN.fogFactor);
    #endif

    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.clipPos);

    #if defined(DEBUG_DISPLAY)
    #if defined(DYNAMICLIGHTMAP_ON)
    inputData.dynamicLightmapUV = IN.dynamicLightmapUV;
    #endif
    #if defined(LIGHTMAP_ON)
    inputData.staticLightmapUV = IN.uvMainAndLM.zw;
    #else
    inputData.vertexSH = SH;
    #endif
    #if defined(USE_APV_PROBE_OCCLUSION)
    inputData.probeOcclusion = input.probeOcclusion;
    #endif
    #endif
}

void InitializeBakedGIData(Varyings IN, inout InputData inputData)
{
    #if defined(_NORMALMAP) && !defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
    half3 SH = 0;
    #else
    half3 SH = IN.vertexSH;
    #endif

#if defined(DYNAMICLIGHTMAP_ON)
    inputData.bakedGI = SAMPLE_GI(IN.uvMainAndLM.zw, IN.dynamicLightmapUV, SH, inputData.normalWS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(IN.uvMainAndLM.zw);
#elif !defined(LIGHTMAP_ON) && (defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2))
    inputData.bakedGI = SAMPLE_GI(SH,
        GetAbsolutePositionWS(inputData.positionWS),
        inputData.normalWS,
        inputData.viewDirectionWS,
        inputData.positionCS.xy,
        IN.probeOcclusion,
        inputData.shadowMask);
#else
    inputData.bakedGI = SAMPLE_GI(IN.uvMainAndLM.zw, SH, inputData.normalWS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(IN.uvMainAndLM.zw);
#endif
}



void SetupTerrainDebugTextureData(inout InputData inputData, float2 uv)
{
    #if defined(DEBUG_DISPLAY)
        #if defined(TERRAIN_SPLAT_ADDPASS)
            if (_DebugMipInfoMode != DEBUGMIPINFOMODE_NONE)
            {
                discard; // Layer 4 & beyond are done additively, doesn't make sense for the mipmap streaming debug views -> stop.
            }
        #endif

        switch (_DebugMipMapTerrainTextureMode)
        {
            case DEBUGMIPMAPMODETERRAINTEXTURE_CONTROL:
                SETUP_DEBUG_TEXTURE_DATA_FOR_TEX(inputData, TRANSFORM_TEX(uv, _Control), _Control);
                break;
            case DEBUGMIPMAPMODETERRAINTEXTURE_LAYER0:
                SETUP_DEBUG_TEXTURE_DATA_FOR_TEX(inputData, TRANSFORM_TEX(uv, _Splat0), _Splat0);
                break;
            case DEBUGMIPMAPMODETERRAINTEXTURE_LAYER1:
                SETUP_DEBUG_TEXTURE_DATA_FOR_TEX(inputData, TRANSFORM_TEX(uv, _Splat1), _Splat1);
                break;
            case DEBUGMIPMAPMODETERRAINTEXTURE_LAYER2:
                SETUP_DEBUG_TEXTURE_DATA_FOR_TEX(inputData, TRANSFORM_TEX(uv, _Splat2), _Splat2);
                break;
            case DEBUGMIPMAPMODETERRAINTEXTURE_LAYER3:
                SETUP_DEBUG_TEXTURE_DATA_FOR_TEX(inputData, TRANSFORM_TEX(uv, _Splat3), _Splat3);
                break;
            default:
                break;
        }

        // TERRAIN_STREAM_INFO: no streamInfo will have been set (no MeshRenderer); set status to "6" to reflect in the debug status that this is a terrain
        // also, set the per-material status to "4" to indicate warnings
        inputData.streamInfo = TERRAIN_STREAM_INFO;
    #endif
}

///////////////////////////////////////////////////////////////////////////////
//                  Vertex and Fragment functions                            //
///////////////////////////////////////////////////////////////////////////////

// Used in Standard Terrain shader
Varyings SplatmapVert(Attributes v)
{
    Varyings o = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    TerrainInstancing(v.positionOS, v.normalOS, v.texcoord);

    VertexPositionInputs Attributes = GetVertexPositionInputs(v.positionOS.xyz);

    o.uvMainAndLM.xy = v.texcoord;
    o.uvMainAndLM.zw = v.texcoord * unity_LightmapST.xy + unity_LightmapST.zw;

#if defined(DYNAMICLIGHTMAP_ON)
    o.dynamicLightmapUV = v.texcoord * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
#endif

    #if defined(_NORMALMAP) && !defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
        half3 viewDirWS = GetWorldSpaceNormalizeViewDir(Attributes.positionWS);
        float4 vertexTangent = float4(cross(float3(0, 0, 1), v.normalOS), 1.0);
        VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, vertexTangent);

        o.normal = half4(normalInput.normalWS, viewDirWS.x);
        o.tangent = half4(normalInput.tangentWS, viewDirWS.y);
        o.bitangent = half4(normalInput.bitangentWS, viewDirWS.z);
    #else
        o.normal = TransformObjectToWorldNormal(v.normalOS);
        OUTPUT_SH4(Attributes.positionWS, o.normal.xyz, GetWorldSpaceNormalizeViewDir(Attributes.positionWS), o.vertexSH, o.probeOcclusion);
    #endif

    half fogFactor = 0;
    #if !defined(_FOG_FRAGMENT)
        fogFactor = ComputeFogFactor(Attributes.positionCS.z);
    #endif

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        o.fogFactorAndVertexLight.x = fogFactor;
        o.fogFactorAndVertexLight.yzw = VertexLighting(Attributes.positionWS, o.normal.xyz);
    #else
        o.fogFactor = fogFactor;
    #endif

    o.positionWS = Attributes.positionWS;
    o.clipPos = Attributes.positionCS;
    

    return o;
}


struct SplatProps
{
    float3 baseColor;
    float3 normal;
    float height;
    float ao;
    float roughness;
};

SplatProps GetSplatProps2(float4 uvMainAndLM,float index,half4 st)
{
    SplatProps props;
    float4 layerBaseMap = SAMPLE_TEXTURE2D_ARRAY( _SplatBaseMapArray,sampler_SplatBaseMapArray, uvMainAndLM.xy*st.xy + st.zw,index );
    float4 layerNormalMask = SAMPLE_TEXTURE2D_ARRAY( _NormalMaskArray,sampler_NormalMaskArray, uvMainAndLM.xy*st.xy + st.zw,index );
    props.baseColor = layerBaseMap.rgb;
    props.height = layerBaseMap.a;
    float2 normalxy = layerNormalMask.xy*2.0f-1.0f;
    props.normal = normalize(float3(normalxy,max(1.0e-16, sqrt(1.0 - saturate(dot(normalxy,normalxy))))));
    props.ao = layerNormalMask.z;
    props.roughness = layerNormalMask.w;
    return props;
}



// Used in Standard Terrain shader
#ifdef TERRAIN_GBUFFER
FragmentOutput SplatmapFragment(Varyings IN)
#else
void SplatmapFragment(
    Varyings IN
    , out half4 outColor : SV_Target0
#ifdef _WRITE_RENDERING_LAYERS
    , out float4 outRenderingLayers : SV_Target1
#endif
    )
#endif
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);
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

    float3 mixColor = SplatProps1.baseColor*weight1 + SplatProps2.baseColor*weight2 + SplatProps3.baseColor*weight3 + SplatProps4.baseColor*weight4 + SplatProps5.baseColor*weight5 + SplatProps6.baseColor*weight6;
    float3 mixNormal = SplatProps1.normal*weight1 + SplatProps2.normal*weight2 + SplatProps3.normal*weight3 +
        SplatProps4.normal*weight4 + SplatProps5.normal*weight5 + SplatProps6.normal*weight6;
    float mixHeight = SplatProps1.height*weight1 + SplatProps2.height*weight2 + SplatProps3.height*weight3 + SplatProps4.height*weight4 + SplatProps5.height*weight5 + SplatProps6.height*weight6;
    float mixAO = SplatProps1.ao*weight1 + SplatProps2.ao*weight2 + SplatProps3.ao*weight3 + SplatProps4.ao*weight4 + SplatProps5.ao*weight5 + SplatProps6.ao*weight6;
    float mixRoughness = SplatProps1.roughness*weight1 + SplatProps2.roughness*weight2 + SplatProps3.roughness*weight3 + SplatProps4.roughness*weight4 + SplatProps5.roughness*weight5 + SplatProps6.roughness*weight6;
    float mixSmoothness = 1.0f - mixRoughness;
    InputData inputData;
    InitializeInputData(IN, mixNormal, inputData);
    SetupTerrainDebugTextureData(inputData, IN.uvMainAndLM.xy);
    InitializeBakedGIData(IN, inputData);
    
    half4 color = StandardPBR(inputData, mixColor, 0, /* specular */ half3(0.0h, 0.0h, 0.0h), mixSmoothness, mixAO, /* emission */ half3(0, 0, 0), 1);

    color.rgb *= color.a;
    color.rgb = MixFog(color.rgb, inputData.fogCoord);
    
    outColor = half4(color.rgb, 1.0h);
    
#ifdef _WRITE_RENDERING_LAYERS
    uint renderingLayers = GetMeshRenderingLayer();
    outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
#endif
}

// Shadow pass

// Shadow Casting Light geometric parameters. These variables are used when applying the shadow Normal Bias and are set by UnityEngine.Rendering.Universal.ShadowUtils.SetupShadowCasterConstantBuffer in com.unity.render-pipelines.universal/Runtime/ShadowUtils.cs
// For Directional lights, _LightDirection is used when applying shadow Normal Bias.
// For Spot lights and Point lights, _LightPosition is used to compute the actual light direction because it is different at each shadow caster geometry vertex.
float3 _LightDirection;
float3 _LightPosition;

struct AttributesLean
{
    float4 position     : POSITION;
    float3 normalOS       : NORMAL;
    float2 texcoord     : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct VaryingsLean
{
    float4 clipPos      : SV_POSITION;
    float2 texcoord     : TEXCOORD0;
    UNITY_VERTEX_OUTPUT_STEREO
};

VaryingsLean ShadowPassVertex(AttributesLean v)
{
    VaryingsLean o = (VaryingsLean)0;
    UNITY_SETUP_INSTANCE_ID(v);
    //instancing处理
    TerrainInstancing(v.position, v.normalOS, v.texcoord);

    float3 positionWS = TransformObjectToWorld(v.position.xyz);
    float3 normalWS = TransformObjectToWorldNormal(v.normalOS);

#if _CASTING_PUNCTUAL_LIGHT_SHADOW
    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
#else
    float3 lightDirectionWS = _LightDirection;
#endif

    float4 clipPos = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

#if UNITY_REVERSED_Z
    clipPos.z = min(clipPos.z, UNITY_NEAR_CLIP_VALUE);
#else
    clipPos.z = max(clipPos.z, UNITY_NEAR_CLIP_VALUE);
#endif

    o.clipPos = clipPos;
    o.texcoord = v.texcoord;

    return o;
}

half4 ShadowPassFragment(VaryingsLean IN) : SV_TARGET
{
#ifdef _ALPHATEST_ON
    ClipHoles(IN.texcoord);
#endif
    return 0;
}

// Depth pass

VaryingsLean DepthOnlyVertex(AttributesLean v)
{
    VaryingsLean o = (VaryingsLean)0;
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    TerrainInstancing(v.position, v.normalOS);
    o.clipPos = TransformObjectToHClip(v.position.xyz);
    o.texcoord = v.texcoord;
    return o;
}

half4 DepthOnlyFragment(VaryingsLean IN) : SV_TARGET
{
#ifdef _ALPHATEST_ON
    ClipHoles(IN.texcoord);
#endif
#ifdef SCENESELECTIONPASS
    // We use depth prepass for scene selection in the editor, this code allow to output the outline correctly
    return half4(_ObjectId, _PassValue, 1.0, 1.0);
#endif
    return IN.clipPos.z;
}

#endif
