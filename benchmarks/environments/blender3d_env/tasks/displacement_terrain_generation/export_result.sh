#!/bin/bash
echo "=== Exporting displacement_terrain_generation result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
BLEND_FILE="/home/ga/BlenderProjects/terrain_scene.blend"
RENDER_FILE="/home/ga/BlenderProjects/terrain_render.png"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check render file
RENDER_EXISTS="false"
RENDER_SIZE="0"
RENDER_CREATED_DURING_TASK="false"

if [ -f "$RENDER_FILE" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c %s "$RENDER_FILE")
    RENDER_MTIME=$(stat -c %Y "$RENDER_FILE")
    if [ "$RENDER_MTIME" -gt "$TASK_START" ]; then
        RENDER_CREATED_DURING_TASK="true"
    fi
fi

# Check blend file and analyze content
BLEND_EXISTS="false"
SCENE_ANALYSIS="{}"

if [ -f "$BLEND_FILE" ]; then
    BLEND_EXISTS="true"
    BLEND_MTIME=$(stat -c %Y "$BLEND_FILE")
    
    # Analyze the scene using Blender Python
    # We look for:
    # 1. High vertex count (subdivision)
    # 2. Displace modifier
    # 3. Procedural texture usage
    # 4. Material color/roughness
    # 5. Camera position
    
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_terrain.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import math

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/terrain_scene.blend")
except:
    pass

result = {
    "max_vertices": 0,
    "has_displace": False,
    "displace_strength": 0.0,
    "displace_texture_type": None,
    "has_procedural_texture": False,
    "material_color": [0.8, 0.8, 0.8, 1.0], # Default grey
    "material_roughness": 0.5,
    "camera_height": 0.0,
    "camera_rotation_x": 0.0
}

# 1. Check Meshes (find the most complex one, assuming it's the terrain)
best_mesh_obj = None
max_verts = 0

for obj in bpy.data.objects:
    if obj.type == 'MESH':
        # Skip the default cube if it hasn't been modified/subdivided much
        verts = len(obj.data.vertices)
        if verts > max_verts:
            max_verts = verts
            best_mesh_obj = obj

result["max_vertices"] = max_verts

# 2. Check Modifiers on the best mesh
if best_mesh_obj:
    for mod in best_mesh_obj.modifiers:
        if mod.type == 'DISPLACE':
            result["has_displace"] = True
            result["displace_strength"] = mod.strength
            
            # 3. Check Texture
            if mod.texture:
                result["displace_texture_type"] = mod.texture.type
                if mod.texture.type in ['CLOUDS', 'MUSGRAVE', 'VORONOI', 'NOISE', 'MARBLE']:
                    result["has_procedural_texture"] = True

    # 4. Check Material
    if len(best_mesh_obj.data.materials) > 0:
        mat = best_mesh_obj.data.materials[0]
        if mat and mat.use_nodes and mat.node_tree:
            # Find Principled BSDF
            bsdf = None
            for node in mat.node_tree.nodes:
                if node.type == "BSDF_PRINCIPLED":
                    bsdf = node
                    break
            
            if bsdf:
                color = bsdf.inputs['Base Color'].default_value
                rough = bsdf.inputs['Roughness'].default_value
                result["material_color"] = list(color)
                result["material_roughness"] = float(rough)

# 5. Check Camera
cam = bpy.context.scene.camera
if cam:
    result["camera_height"] = cam.location.z
    result["camera_rotation_x"] = cam.rotation_euler.x

print("JSON_RESULT:" + json.dumps(result))
PYEOF

    # Run Blender headless
    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    
    # Extract JSON
    PARSED_JSON=$(echo "$ANALYSIS_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
    if [ ! -z "$PARSED_JSON" ]; then
        SCENE_ANALYSIS="$PARSED_JSON"
    fi
    
    rm "$ANALYSIS_SCRIPT"
fi

# Create final JSON result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "render_exists": $RENDER_EXISTS,
    "render_created_during_task": $RENDER_CREATED_DURING_TASK,
    "render_size": $RENDER_SIZE,
    "blend_exists": $BLEND_EXISTS,
    "scene_analysis": $SCENE_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json