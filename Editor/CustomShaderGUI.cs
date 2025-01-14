using UnityEditor;
using UnityEditor.Experimental.Rendering;
using UnityEngine;
using UnityEngine.Rendering;

public class CustomShaderGUI : ShaderGUI
{
    bool AlphaClip {
        set => SetProperty("_AlphaClip", "_AlphaClip", value);
    }
    bool PremultiplyAlpha {
        set=>SetKeyword("_ALPHAPREMULTIPLY_ON",value);
    }
    BlendMode SrcBlend {
        set=>SetProperty("_SrcBlend",(float)value);
    }
    BlendMode DstBlend {
        set=>SetProperty("_DstBlend",(float)value);
    }
    bool ZWrite {
        set=>SetProperty("_ZWrite",value?1f:0f);
    }

    RenderQueue RenderQueue
    {
        set
        {
            foreach (Material m in materials)
            {
                m.renderQueue = (int)value;
            }
        }
    }

    enum ShadowMode { On,Clip, Dither, Off }

    ShadowMode Shadows
    {
        set
        {
            if (SetProperty("_Shadows", (float)value))
            {
                SetKeyword("_SHADOWS_CLIP",value == ShadowMode.Clip);
                SetKeyword("_SHADOWS_DITHER",value == ShadowMode.Dither);
            }
        }
    }

    private bool showPresets;
    private MaterialEditor editor;//Unity 材质编辑器
    private Object[] materials;//当前编辑的材质对象
    private MaterialProperty[] properties;//材质可编辑属性列表
    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        
        EditorGUI.BeginChangeCheck();
        editor = materialEditor;
        materials = materialEditor.targets;
        this.properties = properties;
        //BakedEmission();
        
        EditorGUILayout.Space();
        // showPresets = EditorGUILayout.Foldout(showPresets,"Presets",true);
        // if (showPresets) { }
        EditorGUILayout.BeginHorizontal();
        OpaquePreset();
        ClipPreset();
        FadePreset();
        TransparentPreset();
        EditorGUILayout.EndHorizontal();
        base.OnGUI(materialEditor,properties);
        if (EditorGUI.EndChangeCheck())
        {
            SetShadowCasterPass();
            CopyLightMappingProperties();
        }
    }

    void CopyLightMappingProperties()
    {
        MaterialProperty mainTex = FindProperty("_MainTex", properties, false);
        MaterialProperty baseMap = FindProperty("_BaseMap", properties, false);
        if (mainTex != null && baseMap != null)
        {
            mainTex.textureValue = baseMap.textureValue;
            mainTex.textureScaleAndOffset = baseMap.textureScaleAndOffset;
        }
        MaterialProperty color = FindProperty("_Color", properties, false);
        MaterialProperty baseColor = FindProperty("_BaseColor", properties, false);
        if (color != null && baseColor != null)
        {
            color.colorValue = baseColor.colorValue;
        }
    }

    void BakedEmission()
    {
        EditorGUI.BeginChangeCheck();
        editor.LightmapEmissionProperty();
        if (EditorGUI.EndChangeCheck())
        {
            foreach (Material m in editor.targets)
            {
                m.globalIlluminationFlags &=
                    ~MaterialGlobalIlluminationFlags.EmissiveIsBlack;
            }
        }
    }

    void SetShadowCasterPass()
    {
        MaterialProperty shadows = FindProperty("_Shadows", properties, false);
        if(shadows == null || shadows.hasMixedValue) return;
        bool enabled = shadows.floatValue < (float)ShadowMode.Off;
        foreach (Material m in materials)
        {
            m.SetShaderPassEnabled("ShadowCaster",enabled);
        }
    }

    //用于设置材质属性的值。它通过属性名称找到材质属性，并将其值设置为指定的浮点数值。 
    bool SetProperty(string name, float value)
    {
        MaterialProperty property = FindProperty(name, properties, false);
        if (property != null)
        {
            property.floatValue = value;
            return true;
        }
        return false;
    }
    //用于启用或禁用着色器关键字。它遍历所有材质对象，根据布尔值启用或禁用指定的关键字。
    void SetKeyword(string keyword, bool enabled)
    {
        if (enabled)
        {
            foreach (Material m in materials)
            {
                m.EnableKeyword(keyword);
            }
        }
        else
        {
            foreach (Material m in materials)
            {
                m.DisableKeyword(keyword);
            }
        }
    }

    void SetProperty(string name, string keyword, bool value)
    {
        if (SetProperty(name, value ? 1f : 0f))
        {
            SetKeyword(keyword,value);
        }
    }
    
    
    bool HasProperty(string name)=>FindProperty(name,properties,false)!=null;
    bool HasPremultiplyAlpha => HasProperty("_PremulAlpha");
    

    bool PresetButton(string name)
    {
        if (GUILayout.Button(name))
        {
            editor.RegisterPropertyChangeUndo(name);
            return true;
        }
        return false;
    }

    //不透明预设
    void OpaquePreset()
    {
        if (PresetButton("Opaque"))
        {
            AlphaClip = false;
            PremultiplyAlpha = false;
            SrcBlend = BlendMode.One;
            DstBlend = BlendMode.Zero;
            ZWrite = true;
            RenderQueue = RenderQueue.Geometry;
            Shadows = ShadowMode.On;
        }
    }

    // Opaque的副本，其中开启了裁剪 并将队列设置为 AlphaTest。
    void ClipPreset()
    {
        if (PresetButton("Clip"))
        {
            AlphaClip = true;
            PremultiplyAlpha = false;
            SrcBlend = BlendMode.One;
            DstBlend = BlendMode.Zero;
            ZWrite = true;
            RenderQueue = RenderQueue.AlphaTest;
            Shadows = ShadowMode.Clip;
        }
    }

    // 设置为Fade(Alpha Blend,高光不完全保留)材质预设值
    void FadePreset()
    {
        if (PresetButton("Fade"))
        {
            AlphaClip = false;
            PremultiplyAlpha = false;
            SrcBlend = BlendMode.SrcAlpha;
            DstBlend = BlendMode.OneMinusSrcAlpha;
            ZWrite = false;
            RenderQueue = RenderQueue.Transparent;
            Shadows = ShadowMode.Dither;
        }
    }
    
    // 设置为Transparent(开启Premultiply Alpha)材质预设值,高光完全保留
    void TransparentPreset()
    {
        if (HasPremultiplyAlpha && PresetButton("Transparent"))
        {
            AlphaClip = false;
            PremultiplyAlpha = true;
            SrcBlend = BlendMode.One;
            DstBlend = BlendMode.OneMinusSrcAlpha;
            ZWrite = false;
            RenderQueue = RenderQueue.Transparent;
            Shadows = ShadowMode.Dither;
        }
    }
    
}

















