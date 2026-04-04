#!/bin/bash
echo "=== Exporting VR Panorama Render result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
OUTPUT_BLEND="/home/ga/BlenderProjects/classroom_vr_setup.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/classroom_360.png"

# 1. Analyze the saved .blend file using Blender Python (headless)
# We need to verify internal settings that aren't visible in screenshots
ANALYSIS_JSON="{}"
if [ -f "$OUTPUT_BLEND" ]; then
    echo "Analyzing saved blend file..."
    
    # Python script to extract scene data
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_vr.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import math

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/classroom_vr_setup.blend")
    
    scene = bpy.context.scene
    cam = scene.camera
    
    data = {
        "valid_file": True,
        "render_engine": scene.render.engine,
        "resolution_x": scene.render.resolution_x,
        "resolution_y": scene.render.resolution_y,
        "resolution_percentage": scene.render.resolution_percentage,
        "camera_found": False
    }

    if cam:
        data["camera_found"] = True
        data["camera_type"] = cam.data.type
        # Panorama type only exists if type is PANO (usually)
        # We use getattr to be safe
        data["panorama_type"] = getattr(cam.data, "panorama_type", "NONE")
        data["location"] = [round(v, 4) for v in cam.location]
        data["rotation_euler"] = [round(v, 4) for v in cam.rotation_euler]
        
    print("JSON_RESULT:" + json.dumps(data))
except Exception as e:
    print("JSON_RESULT:" + json.dumps({"valid_file": False, "error": str(e)}))
PYEOF

    # Run Blender in background
    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    # Extract the JSON line
    ANALYSIS_JSON=$(echo "$ANALYSIS_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
    rm "$ANALYSIS_SCRIPT"
else
    ANALYSIS_JSON='{"valid_file": false, "error": "File not found"}'
fi

# 2. Check Render Output
RENDER_EXISTS="false"
RENDER_SIZE="0"
RENDER_WIDTH="0"
RENDER_HEIGHT="0"
RENDER_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$OUTPUT_RENDER")
    RENDER_MTIME=$(stat -c%Y "$OUTPUT_RENDER")
    
    if [ "$RENDER_MTIME" -gt "$TASK_START" ]; then
        RENDER_CREATED_DURING_TASK="true"
    fi
    
    # Get dimensions using simple python one-liner (assuming PIL installed in env)
    DIMENSIONS=$(python3 -c "import sys; from PIL import Image; i=Image.open('$OUTPUT_RENDER'); print(f'{i.width} {i.height}')" 2>/dev/null || echo "0 0")
    RENDER_WIDTH=$(echo "$DIMENSIONS" | awk '{print $1}')
    RENDER_HEIGHT=$(echo "$DIMENSIONS" | awk '{print $2}')
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Construct Final JSON
# Use temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scene_analysis": $ANALYSIS_JSON,
    "render_check": {
        "exists": $RENDER_EXISTS,
        "created_during_task": $RENDER_CREATED_DURING_TASK,
        "size_bytes": $RENDER_SIZE,
        "width": $RENDER_WIDTH,
        "height": $RENDER_HEIGHT
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="