#!/bin/bash
set -e
echo "=== Exporting Ocean Seascape Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Define Paths
PROJECT_DIR="/home/ga/BlenderProjects"
SCENE_FILE="$PROJECT_DIR/ocean_scene.blend"
RENDER_FILE="$PROJECT_DIR/ocean_render.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# 3. Basic File Checks
SCENE_EXISTS="false"
RENDER_EXISTS="false"
RENDER_SIZE=0
RENDER_NEW="false"

if [ -f "$SCENE_FILE" ]; then
    SCENE_EXISTS="true"
fi

if [ -f "$RENDER_FILE" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$RENDER_FILE")
    RENDER_MTIME=$(stat -c%Y "$RENDER_FILE")
    
    if [ "$RENDER_MTIME" -gt "$TASK_START" ]; then
        RENDER_NEW="true"
    fi
fi

# 4. Deep Inspection using Blender Python (Headless)
# We inspect the .blend file to verify the Ocean modifier, lights, and camera.
INSPECTION_SCRIPT="/tmp/inspect_ocean_scene.py"
cat > "$INSPECTION_SCRIPT" << 'PYEOF'
import bpy
import json
import math
import sys

# Output structure
data = {
    "has_ocean_modifier": False,
    "ocean_resolution": 0,
    "ocean_size": 0,
    "world_color_warm": False,
    "world_color_rgb": [0, 0, 0],
    "has_sun_light": False,
    "sun_low_angle": False,
    "camera_valid": False,
    "camera_height": 0,
    "object_count": 0
}

try:
    # Open the student's file
    bpy.ops.wm.open_mainfile(filepath=sys.argv[-1])
    
    data["object_count"] = len(bpy.data.objects)

    # 1. Check for Ocean Modifier
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            for mod in obj.modifiers:
                if mod.type == 'OCEAN':
                    data["has_ocean_modifier"] = True
                    # Check resolution (viewport or render)
                    res = getattr(mod, "resolution", 7) # Default is 7
                    data["ocean_resolution"] = res
                    # Check spatial size
                    data["ocean_size"] = getattr(mod, "spatial_size", 50)
                    break
        if data["has_ocean_modifier"]:
            break

    # 2. Check World Background
    world = bpy.context.scene.world
    if world and world.use_nodes and world.node_tree:
        # Try to find Background node color
        bg_node = None
        for node in world.node_tree.nodes:
            if node.type == 'BACKGROUND':
                bg_node = node
                break
        
        if bg_node:
            color = bg_node.inputs[0].default_value
            data["world_color_rgb"] = [float(color[0]), float(color[1]), float(color[2])]
            # Warm check: Red > 0.3 AND Red > Blue
            if color[0] > 0.3 and color[0] > color[2]:
                data["world_color_warm"] = True
    elif world:
        # No nodes, simple color
        color = world.color
        data["world_color_rgb"] = [float(color[0]), float(color[1]), float(color[2])]
        if color[0] > 0.3 and color[0] > color[2]:
            data["world_color_warm"] = True

    # 3. Check Sun Light
    for obj in bpy.data.objects:
        if obj.type == 'LIGHT' and obj.data.type == 'SUN':
            data["has_sun_light"] = True
            # Check rotation (Z direction)
            # A simple heuristic: if it's pointing straight down, X/Y rot is 0.
            # We want "low angle", meaning the light direction is more horizontal.
            # In Blender, rotation_euler X=0 is often horizontal or vertical depending on convention,
            # but usually default sun points somewhat down. 
            # We check if the Z component of the direction vector is not -1 (straight down).
            
            # Get light direction vector
            direction = obj.matrix_world.to_quaternion() @ bpy.mathutils.Vector((0, 0, -1))
            # If Z is near 0, it's horizontal (sunset). If Z is -1, it's noon.
            # We accept anything where Z > -0.9 (not strictly noon)
            if direction.z > -0.9:
                data["sun_low_angle"] = True
            break

    # 4. Check Camera
    cam = bpy.context.scene.camera
    if cam:
        data["camera_valid"] = True
        data["camera_height"] = cam.location.z

except Exception as e:
    data["error"] = str(e)

print("JSON_START")
print(json.dumps(data))
print("JSON_END")
PYEOF

SCENE_DATA="{}"
if [ "$SCENE_EXISTS" = "true" ]; then
    # Run inspection
    OUTPUT=$(/opt/blender/blender --background --python "$INSPECTION_SCRIPT" -- "$SCENE_FILE" 2>/dev/null)
    
    # Extract JSON
    JSON_STR=$(echo "$OUTPUT" | awk '/JSON_START/{flag=1; next} /JSON_END/{flag=0} flag')
    if [ -n "$JSON_STR" ]; then
        SCENE_DATA="$JSON_STR"
    fi
fi

# 5. Compile Final JSON
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "scene_exists": $SCENE_EXISTS,
    "render_exists": $RENDER_EXISTS,
    "render_size": $RENDER_SIZE,
    "render_new": $RENDER_NEW,
    "scene_data": $SCENE_DATA
}
EOF

# Permissions
chmod 666 "$RESULT_JSON"

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="