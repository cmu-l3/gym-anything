#!/bin/bash
echo "=== Exporting debug_broken_render result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# ================================================================
# CONFIGURATION
# ================================================================
EXPECTED_BLEND="/home/ga/BlenderProjects/fixed_scene.blend"
EXPECTED_RENDER="/home/ga/BlenderProjects/fixed_render.png"

# ================================================================
# CHECK BLEND FILE EXISTS
# ================================================================
BLEND_EXISTS="false"
BLEND_SIZE="0"
BLEND_MTIME="0"

if [ -f "$EXPECTED_BLEND" ]; then
    BLEND_EXISTS="true"
    BLEND_SIZE=$(stat -c%s "$EXPECTED_BLEND" 2>/dev/null || echo "0")
    BLEND_MTIME=$(stat -c%Y "$EXPECTED_BLEND" 2>/dev/null || echo "0")
fi

# ================================================================
# CHECK RENDER OUTPUT
# ================================================================
RENDER_EXISTS="false"
RENDER_SIZE="0"
RENDER_MTIME="0"
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="none"

if [ -f "$EXPECTED_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$EXPECTED_RENDER" 2>/dev/null || echo "0")
    RENDER_MTIME=$(stat -c%Y "$EXPECTED_RENDER" 2>/dev/null || echo "0")

    # Get image dimensions using Python/PIL
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/BlenderProjects/fixed_render.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format, "mode": img.mode}))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "unknown", "mode": "unknown"}))
PYEOF
)
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))")
fi

# ================================================================
# ANALYZE SAVED BLEND FILE VIA BLENDER PYTHON (HEADLESS)
# ================================================================
SCENE_ANALYSIS="{}"

if [ "$BLEND_EXISTS" = "true" ]; then
    echo "Analyzing fixed_scene.blend..."

    ANALYZE_SCRIPT=$(mktemp /tmp/analyze_scene.XXXXXX.py)
    cat > "$ANALYZE_SCRIPT" << 'PYEOF'
import bpy
import json
import math
import mathutils

# Open the saved blend file
bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/fixed_scene.blend")

scene = bpy.context.scene
analysis = {}

# ================================================================
# Camera Analysis
# ================================================================
camera = bpy.data.objects.get('MainCamera')
if camera is None:
    for obj in bpy.data.objects:
        if obj.type == 'CAMERA':
            camera = obj
            break

camera_info = {
    "found": False,
    "faces_scene": False,
    "has_tracking_constraint": False,
    "dot_product": 0.0,
    "forward_vector": [0, 0, 0],
    "location": [0, 0, 0],
    "rotation_euler": [0, 0, 0],
    "constraints": []
}

if camera:
    camera_info["found"] = True
    camera_info["name"] = camera.name
    camera_info["location"] = [round(v, 4) for v in camera.location]
    camera_info["rotation_euler"] = [round(v, 4) for v in camera.rotation_euler]
    camera_info["constraints"] = [c.type for c in camera.constraints]

    # Check for Track To constraint
    for constraint in camera.constraints:
        if constraint.type == 'TRACK_TO':
            camera_info["has_tracking_constraint"] = True
            camera_info["tracking_target"] = constraint.target.name if constraint.target else None
            break

    # Compute camera forward vector: camera looks along -Z in local space
    forward = camera.matrix_world.to_quaternion() @ mathutils.Vector((0, 0, -1))
    camera_info["forward_vector"] = [round(v, 4) for v in forward]

    # Check if forward vector points toward scene center (roughly the origin)
    cam_to_origin = mathutils.Vector((0, 0, 0)) - camera.location
    cam_to_origin_len = cam_to_origin.length
    if cam_to_origin_len > 0.001:
        dot = forward.dot(cam_to_origin.normalized())
        camera_info["dot_product"] = round(dot, 4)
        # dot > 0 means camera faces toward the scene
        camera_info["faces_scene"] = (dot > 0) or camera_info["has_tracking_constraint"]
    else:
        # Camera is at origin, so it is at the scene
        camera_info["faces_scene"] = True

analysis["camera"] = camera_info

# ================================================================
# Light Analysis
# ================================================================
lights = []
for obj in bpy.data.objects:
    if obj.type == 'LIGHT' and obj.data:
        light_info = {
            "name": obj.name,
            "type": obj.data.type,
            "energy": round(obj.data.energy, 4),
            "location": [round(v, 3) for v in obj.location]
        }
        lights.append(light_info)

analysis["lights"] = lights

# Find the main sun light specifically
sun_light = bpy.data.objects.get('SunLight')
if sun_light is None:
    for obj in bpy.data.objects:
        if obj.type == 'LIGHT':
            sun_light = obj
            break

if sun_light and sun_light.data:
    analysis["main_light_energy"] = round(sun_light.data.energy, 4)
    analysis["main_light_name"] = sun_light.name
else:
    analysis["main_light_energy"] = 0.0
    analysis["main_light_name"] = None

# ================================================================
# Render Settings Analysis
# ================================================================
analysis["render_engine"] = scene.render.engine
analysis["resolution_x"] = scene.render.resolution_x
analysis["resolution_y"] = scene.render.resolution_y
analysis["resolution_percentage"] = scene.render.resolution_percentage

# Effective resolution (accounting for percentage)
eff_x = int(scene.render.resolution_x * scene.render.resolution_percentage / 100)
eff_y = int(scene.render.resolution_y * scene.render.resolution_percentage / 100)
analysis["effective_resolution_x"] = eff_x
analysis["effective_resolution_y"] = eff_y

if scene.render.engine == 'CYCLES':
    analysis["cycles_samples"] = scene.cycles.samples
else:
    analysis["cycles_samples"] = 0

# ================================================================
# BaseCube Visibility Analysis
# ================================================================
base_cube = bpy.data.objects.get('BaseCube')
if base_cube is None:
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and 'cube' in obj.name.lower():
            base_cube = obj
            break

cube_info = {
    "found": False,
    "hide_render": True,
    "hide_viewport": False,
    "visible_get": False
}

if base_cube:
    cube_info["found"] = True
    cube_info["name"] = base_cube.name
    cube_info["hide_render"] = base_cube.hide_render
    cube_info["hide_viewport"] = base_cube.hide_viewport
    cube_info["visible_get"] = base_cube.visible_get()
    cube_info["location"] = [round(v, 3) for v in base_cube.location]

analysis["base_cube"] = cube_info

# ================================================================
# Full Object List
# ================================================================
objects_list = []
for obj in bpy.data.objects:
    obj_info = {
        "name": obj.name,
        "type": obj.type,
        "location": [round(v, 3) for v in obj.location],
        "hide_render": obj.hide_render,
        "hide_viewport": obj.hide_viewport
    }
    objects_list.append(obj_info)

analysis["object_count"] = len(bpy.data.objects)
analysis["objects"] = objects_list

print("SCENE_ANALYSIS_JSON:" + json.dumps(analysis))
PYEOF

    ANALYZE_OUTPUT=$(/opt/blender/blender --background --python "$ANALYZE_SCRIPT" 2>/dev/null)
    ANALYSIS_LINE=$(echo "$ANALYZE_OUTPUT" | grep '^SCENE_ANALYSIS_JSON:' | head -1)

    if [ -n "$ANALYSIS_LINE" ]; then
        SCENE_ANALYSIS="${ANALYSIS_LINE#SCENE_ANALYSIS_JSON:}"
    else
        echo "WARNING: Could not extract scene analysis from Blender output"
        SCENE_ANALYSIS='{"error": "Failed to analyze blend file"}'
    fi

    rm -f "$ANALYZE_SCRIPT"
fi

# ================================================================
# CHECK BLENDER STATE
# ================================================================
BLENDER_RUNNING="false"
BLENDER_PID=""
BLENDER_WINDOW_TITLE=""

if pgrep -x "blender" > /dev/null 2>&1; then
    BLENDER_RUNNING="true"
    BLENDER_PID=$(pgrep -x "blender" | head -1)
fi

# Get Blender window title
BLENDER_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "blender" || echo "")
if [ -n "$BLENDER_WINDOWS" ]; then
    BLENDER_WINDOW_TITLE=$(echo "$BLENDER_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "blend_exists": $BLEND_EXISTS,
    "blend_size_bytes": $BLEND_SIZE,
    "blend_mtime": $BLEND_MTIME,
    "blend_path": "$EXPECTED_BLEND",
    "render_exists": $RENDER_EXISTS,
    "render_size_bytes": $RENDER_SIZE,
    "render_mtime": $RENDER_MTIME,
    "render_path": "$EXPECTED_RENDER",
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "blender_was_running": $BLENDER_RUNNING,
    "blender_window_title": "$BLENDER_WINDOW_TITLE",
    "scene_analysis": $SCENE_ANALYSIS,
    "screenshot_path": "/tmp/task_end.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
