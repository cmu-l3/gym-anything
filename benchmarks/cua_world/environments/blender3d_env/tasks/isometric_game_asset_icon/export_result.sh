#!/bin/bash
echo "=== Exporting Isometric Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Paths
RENDER_OUTPUT="/home/ga/BlenderProjects/iso_icon.png"
BLEND_OUTPUT="/home/ga/BlenderProjects/iso_setup.blend"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Render Output
RENDER_EXISTS="false"
RENDER_CREATED_DURING_TASK="false"
RENDER_WIDTH="0"
RENDER_HEIGHT="0"
HAS_ALPHA="false"

if [ -f "$RENDER_OUTPUT" ]; then
    RENDER_EXISTS="true"
    RENDER_MTIME=$(stat -c %Y "$RENDER_OUTPUT" 2>/dev/null || echo "0")
    
    if [ "$RENDER_MTIME" -gt "$TASK_START" ]; then
        RENDER_CREATED_DURING_TASK="true"
    fi
    
    # Analyze Image using Python
    IMG_ANALYSIS=$(python3 << 'PYEOF'
import json
import sys
try:
    from PIL import Image
    img = Image.open("/home/ga/BlenderProjects/iso_icon.png")
    
    # Check for alpha channel
    has_alpha = img.mode in ('RGBA', 'LA') or (img.mode == 'P' and 'transparency' in img.info)
    
    # Simple check: Corner pixel should be transparent (alpha 0)
    # Center pixel should be opaque (alpha > 0)
    w, h = img.size
    corner = img.getpixel((0, 0))
    center = img.getpixel((w//2, h//2))
    
    corner_alpha = corner[3] if len(corner) > 3 else 255
    center_alpha = center[3] if len(center) > 3 else 255
    
    print(json.dumps({
        "width": w,
        "height": h,
        "has_alpha": has_alpha,
        "corner_transparent": corner_alpha == 0,
        "center_opaque": center_alpha > 0
    }))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
    )
fi

# 2. Check Blender File State (Headless)
BLEND_EXISTS="false"
SCENE_DATA="{}"

if [ -f "$BLEND_OUTPUT" ]; then
    BLEND_EXISTS="true"
    
    # Run Blender Python script to extract scene data
    # We use a temp script to avoid complex escaping
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_iso.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import math

try:
    # Open the saved file
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/iso_setup.blend")
    
    scene = bpy.context.scene
    camera = scene.camera
    render = scene.render
    
    # Camera Data
    cam_data = {}
    if camera:
        cam_data = {
            "type": camera.data.type,
            "rotation_euler": [math.degrees(a) for a in camera.rotation_euler],
            "scale": camera.data.ortho_scale
        }
    
    # Objects (check for floor)
    # The default floor in BMW scene is usually named "Plane" or similar
    floor_exists = False
    floor_visible = False
    for obj in bpy.data.objects:
        if "plane" in obj.name.lower() or "floor" in obj.name.lower() or "ground" in obj.name.lower():
            floor_exists = True
            # Check visibility (viewport and render)
            if not obj.hide_render:
                floor_visible = True
    
    result = {
        "resolution_x": render.resolution_x,
        "resolution_y": render.resolution_y,
        "film_transparent": render.film_transparent,
        "camera": cam_data,
        "floor_visible_render": floor_visible
    }
    
    print("JSON_RESULT:" + json.dumps(result))
    
except Exception as e:
    print("JSON_RESULT:" + json.dumps({"error": str(e)}))
PYEOF

    # Run blender headless
    BLENDER_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    
    # Extract JSON line
    SCENE_DATA=$(echo "$BLENDER_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
    rm -f "$ANALYSIS_SCRIPT"
fi

# Combine results into final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "render_exists": $RENDER_EXISTS,
    "render_created_during_task": $RENDER_CREATED_DURING_TASK,
    "image_analysis": ${IMG_ANALYSIS:-null},
    "blend_exists": $BLEND_EXISTS,
    "scene_data": ${SCENE_DATA:-null},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json