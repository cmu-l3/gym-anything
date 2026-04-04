#!/bin/bash
echo "=== Exporting molecular_pdb_viz_styling result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check files
EXPECTED_BLEND="/home/ga/BlenderProjects/molecular_setup.blend"
EXPECTED_RENDER="/home/ga/BlenderProjects/caffeine_viz.png"

BLEND_EXISTS="false"
RENDER_EXISTS="false"
RENDER_SIZE="0"

if [ -f "$EXPECTED_BLEND" ]; then BLEND_EXISTS="true"; fi
if [ -f "$EXPECTED_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$EXPECTED_RENDER")
fi

# 3. Analyze the saved Blend file using Blender Python
# We check: Add-on status, Object count, Material properties
ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_mol.XXXXXX.py)
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json

result = {
    "addon_enabled": False,
    "object_count": 0,
    "materials": {}
}

# Check Add-on (User Preferences)
# Note: Add-on enabling persists in user prefs, but might not be saved in file. 
# We check if the addon module is loaded or enabled in prefs.
try:
    if 'io_mesh_atomic' in bpy.context.preferences.addons:
        result["addon_enabled"] = True
except:
    pass

# Open the saved file to check content
try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/molecular_setup.blend")
    
    # Check objects (excluding default Cube/Camera/Light if possible, but raw count is usually enough for a molecule)
    # Caffeine has ~14 heavy atoms + bonds. Default scene has 3 objects.
    result["object_count"] = len(bpy.data.objects)

    # Analyze Materials
    # Look for materials with specific names (Atomic Blender creates them based on element)
    for mat in bpy.data.materials:
        mat_info = {
            "name": mat.name,
            "base_color": [1.0, 1.0, 1.0, 1.0],
            "roughness": 0.5,
            "emission_strength": 0.0,
            "emission_color": [0.0, 0.0, 0.0, 1.0]
        }
        
        if mat.use_nodes and mat.node_tree:
            # Find Principled BSDF
            bsdf = None
            for node in mat.node_tree.nodes:
                if node.type == "BSDF_PRINCIPLED":
                    bsdf = node
                    break
            
            if bsdf:
                # Base Color
                if "Base Color" in bsdf.inputs:
                    mat_info["base_color"] = list(bsdf.inputs["Base Color"].default_value)
                
                # Roughness
                if "Roughness" in bsdf.inputs:
                    mat_info["roughness"] = bsdf.inputs["Roughness"].default_value
                
                # Emission
                if "Emission Strength" in bsdf.inputs:
                    mat_info["emission_strength"] = bsdf.inputs["Emission Strength"].default_value
                if "Emission Color" in bsdf.inputs: # 4.0+
                    mat_info["emission_color"] = list(bsdf.inputs["Emission Color"].default_value)
                elif "Emission" in bsdf.inputs: # Older versions
                    mat_info["emission_color"] = list(bsdf.inputs["Emission"].default_value)

        result["materials"][mat.name] = mat_info

except Exception as e:
    result["error"] = str(e)

print("JSON_RESULT:" + json.dumps(result))
PYEOF

# Run Blender in background
ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)

# Extract JSON
JSON_DATA=$(echo "$ANALYSIS_OUTPUT" | grep "^JSON_RESULT:" | sed 's/JSON_RESULT://')

if [ -z "$JSON_DATA" ]; then
    JSON_DATA='{"error": "Failed to run analysis script"}'
fi

# 4. Construct final result
cat > /tmp/task_result.json << EOF
{
    "blend_exists": $BLEND_EXISTS,
    "render_exists": $RENDER_EXISTS,
    "render_size": $RENDER_SIZE,
    "scene_analysis": $JSON_DATA,
    "task_end_time": $(date +%s)
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json