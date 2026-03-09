#!/bin/bash
echo "=== Exporting studio_product_lighting result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# ================================================================
# CONFIGURATION
# ================================================================
EXPECTED_BLEND="/home/ga/BlenderProjects/studio_setup.blend"
EXPECTED_RENDER="/home/ga/BlenderProjects/product_shot.png"

# ================================================================
# GET INITIAL STATE (recorded by setup_task.sh)
# ================================================================
INITIAL_LIGHT_COUNT="0"
INITIAL_OBJECT_COUNT="0"

if [ -f /tmp/initial_state.json ]; then
    INITIAL_LIGHT_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_scene', {}).get('light_count', 0))" 2>/dev/null || echo "0")
    INITIAL_OBJECT_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_scene', {}).get('object_count', 0))" 2>/dev/null || echo "0")
fi

# ================================================================
# CHECK BLEND FILE OUTPUT
# ================================================================
BLEND_EXISTS="false"
BLEND_SIZE="0"
BLEND_VALID="false"
BLEND_CREATED="false"

if [ -f "$EXPECTED_BLEND" ]; then
    BLEND_EXISTS="true"
    BLEND_SIZE=$(stat -c%s "$EXPECTED_BLEND" 2>/dev/null || echo "0")

    # Check magic bytes for valid blend file
    MAGIC=$(head -c 7 "$EXPECTED_BLEND" 2>/dev/null | tr -d '\0')
    if [ "$MAGIC" = "BLENDER" ]; then
        BLEND_VALID="true"
    fi

    BLEND_CREATED="true"
fi

# ================================================================
# ANALYZE SAVED BLEND FILE FOR LIGHTS, CAMERA, WORLD
# ================================================================
SCENE_ANALYSIS='{"error": "no blend file"}'

if [ "$BLEND_EXISTS" = "true" ] && [ "$BLEND_VALID" = "true" ]; then
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_scene.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import math

bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/studio_setup.blend")

# --- Collect all lights ---
lights = []
for obj in bpy.data.objects:
    if obj.type == 'LIGHT':
        light_data = obj.data
        light_info = {
            "name": obj.name,
            "light_type": light_data.type if light_data else "UNKNOWN",
            "location": [round(v, 4) for v in obj.location],
            "energy": round(light_data.energy, 2) if light_data else 0,
            "color": [round(c, 3) for c in light_data.color] if light_data else [1, 1, 1]
        }
        if light_data and light_data.type == 'AREA':
            light_info["size"] = round(light_data.size, 3)
        if light_data and light_data.type == 'SPOT':
            light_info["spot_size"] = round(light_data.spot_size, 3)
            light_info["spot_blend"] = round(light_data.spot_blend, 3)
        lights.append(light_info)

# --- Collect camera info ---
cameras = [o for o in bpy.data.objects if o.type == 'CAMERA']
camera_info = {}
if cameras:
    cam = cameras[0]
    loc = cam.location
    camera_info = {
        "name": cam.name,
        "location": [round(v, 4) for v in loc],
        "rotation_euler": [round(v, 4) for v in cam.rotation_euler],
        "height": round(loc.z, 4),
        "distance_from_origin": round(math.sqrt(loc.x**2 + loc.y**2 + loc.z**2), 4)
    }

# --- Collect world/environment info ---
world_info = {"color": [0.5, 0.5, 0.5], "strength": 1.0, "brightness": 0.5}
world = bpy.context.scene.world
if world and world.use_nodes:
    for node in world.node_tree.nodes:
        if node.type == 'BACKGROUND':
            color = node.inputs['Color'].default_value
            strength = node.inputs['Strength'].default_value
            # Compute perceived brightness (luminance)
            r, g, b = color[0], color[1], color[2]
            brightness = 0.2126 * r + 0.7152 * g + 0.0722 * b
            world_info = {
                "color": [round(color[0], 4), round(color[1], 4), round(color[2], 4)],
                "strength": round(strength, 4),
                "brightness": round(brightness * strength, 4)
            }
            break

# --- Collect all objects ---
objects = []
for obj in bpy.data.objects:
    objects.append({
        "name": obj.name,
        "type": obj.type,
        "location": [round(v, 3) for v in obj.location]
    })

# --- Count by type ---
light_type_counts = {}
for lt in lights:
    t = lt["light_type"]
    light_type_counts[t] = light_type_counts.get(t, 0) + 1

result = {
    "object_count": len(bpy.data.objects),
    "light_count": len(lights),
    "lights": lights,
    "light_type_counts": light_type_counts,
    "area_or_spot_count": light_type_counts.get("AREA", 0) + light_type_counts.get("SPOT", 0),
    "camera": camera_info,
    "world": world_info,
    "objects": objects,
    "render_engine": bpy.context.scene.render.engine,
    "resolution": [bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y]
}

print("ANALYSIS_JSON:" + json.dumps(result))
PYEOF

    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    ANALYSIS_LINE=$(echo "$ANALYSIS_OUTPUT" | grep '^ANALYSIS_JSON:' | head -1)

    if [ -n "$ANALYSIS_LINE" ]; then
        SCENE_ANALYSIS="${ANALYSIS_LINE#ANALYSIS_JSON:}"
    else
        SCENE_ANALYSIS='{"error": "could not parse blender output", "light_count": 0, "lights": [], "light_type_counts": {}, "area_or_spot_count": 0, "camera": {}, "world": {"color": [0.5, 0.5, 0.5], "strength": 1.0, "brightness": 0.5}, "objects": [], "object_count": 0}'
    fi

    rm -f "$ANALYSIS_SCRIPT"
fi

# Extract key values from analysis
CURRENT_LIGHT_COUNT=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('light_count', 0))" 2>/dev/null || echo "0")
AREA_OR_SPOT_COUNT=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('area_or_spot_count', 0))" 2>/dev/null || echo "0")
LIGHTS_JSON=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('lights', [])))" 2>/dev/null || echo "[]")
LIGHT_TYPE_COUNTS_JSON=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('light_type_counts', {})))" 2>/dev/null || echo "{}")
CAMERA_JSON=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('camera', {})))" 2>/dev/null || echo "{}")
WORLD_JSON=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('world', {})))" 2>/dev/null || echo "{}")
CURRENT_OBJECT_COUNT=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('object_count', 0))" 2>/dev/null || echo "0")
OBJECTS_JSON=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('objects', [])))" 2>/dev/null || echo "[]")

# ================================================================
# CHECK RENDER OUTPUT
# ================================================================
RENDER_EXISTS="false"
RENDER_SIZE="0"
RENDER_WIDTH="0"
RENDER_HEIGHT="0"
RENDER_FORMAT="none"

if [ -f "$EXPECTED_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$EXPECTED_RENDER" 2>/dev/null || echo "0")

    # Get image dimensions and format using Python/PIL
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/BlenderProjects/product_shot.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown", "mode": img.mode}))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "unknown", "mode": "unknown"}))
PYEOF
)
    RENDER_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    RENDER_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    RENDER_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
fi

# ================================================================
# CHECK BLENDER STATE
# ================================================================
BLENDER_RUNNING="false"
BLENDER_WINDOW_TITLE=""

if pgrep -x "blender" > /dev/null 2>&1; then
    BLENDER_RUNNING="true"
fi

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
    "blend_valid": $BLEND_VALID,
    "blend_created": $BLEND_CREATED,
    "blend_path": "$EXPECTED_BLEND",
    "render_exists": $RENDER_EXISTS,
    "render_size_bytes": $RENDER_SIZE,
    "render_width": $RENDER_WIDTH,
    "render_height": $RENDER_HEIGHT,
    "render_format": "$RENDER_FORMAT",
    "render_path": "$EXPECTED_RENDER",
    "initial_light_count": $INITIAL_LIGHT_COUNT,
    "initial_object_count": $INITIAL_OBJECT_COUNT,
    "current_light_count": $CURRENT_LIGHT_COUNT,
    "current_object_count": $CURRENT_OBJECT_COUNT,
    "area_or_spot_count": $AREA_OR_SPOT_COUNT,
    "lights": $LIGHTS_JSON,
    "light_type_counts": $LIGHT_TYPE_COUNTS_JSON,
    "camera": $CAMERA_JSON,
    "world": $WORLD_JSON,
    "objects": $OBJECTS_JSON,
    "blender_was_running": $BLENDER_RUNNING,
    "blender_window_title": "$BLENDER_WINDOW_TITLE",
    "screenshot_path": "/tmp/task_end.png",
    "initial_screenshot_path": "/tmp/task_start.png",
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
