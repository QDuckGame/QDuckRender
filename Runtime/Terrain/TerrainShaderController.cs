using UnityEngine;

public class TerrainShaderController : MonoBehaviour
{
	public Terrain terrain;
    private Material terrainMaterial;

    void Start()
    {
        if (terrain == null)
        {
            terrain = GetComponent<Terrain>();
        }

        if (terrain != null)
        {
            terrainMaterial = terrain.materialTemplate;
            UpdateShaderProperties();
        }
    }
    
#if UNITY_EDITOR
    void Update()
    {
        if (terrain != null && !Application.isPlaying)
        {
            UpdateShaderProperties();
        }
    }
#endif
    
    void UpdateShaderProperties()
    {
        if (terrainMaterial != null)
        {
            float terrainWidth = terrain.terrainData.size.x;
            float terrainLength = terrain.terrainData.size.z;
            terrainMaterial.SetVector("_TerrainSize", new Vector4(terrainWidth, terrainLength, 0, 0));
        }
    }
}