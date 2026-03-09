#!/bin/bash
set -e
echo "=== Exporting EEVEE migration task results ==="

# Define paths
BLEND_FILE="/home/ga/BlenderProjects/eevee_scene.blend"
RENDER_FILE="/home/ga/BlenderProjects/eevee_render.png"
RESULT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Check Render Output ---
RENDER_EXISTS="false"
RENDER_SIZE=0
RENDER_WIDTH=0
RENDER_HEIGHT=0
RENDER_NEWER="false"

if [ -f "$RENDER_FILE" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$RENDER_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    RENDER_MTIME=$(stat -c%Y "$RENDER_FILE" 2>/dev/null || echo "0")
    if [ "$RENDER_MTIME" -gt "$TASK_START" ]; then
        RENDER_NEWER="true"
    fi

    # Get dimensions using Python
    DIMS=$(python3 -c "
import sys, json
try:
    from PIL import Image
    img = Image.open('$RENDER_FILE')
    print(f'{img.width} {img.height}')
except Exception:
    print('0 0')
" 2>/dev/null || echo "0 0")
    
    RENDER_WIDTH=$(echo "$DIMS" | awk '{print $1}')
    RENDER_HEIGHT=$(echo "$DIMS" | awk '{print $2}')
fi

# --- Check Blend File & Extract Settings ---
BLEND_EXISTS="false"
BLEND_VALID="false"
BLEND_NEWER="false"
SCENE_DATA="{}"

if [ -f "$BLEND_FILE" ]; then
    BLEND_EXISTS="true"
    
    # Check timestamp
    BLEND_MTIME=$(stat -c%Y "$BLEND_FILE" 2>/dev/null || echo "0")
    if [ "$BLEND_MTIME" -gt "$TASK_START" ]; then
        BLEND_NEWER="true"
    fi

    # Check magic bytes
    MAGIC=$(head -c 7 "$BLEND_FILE" 2>/dev/null || echo "")
    if [ "$MAGIC" = "BLENDER" ]; then
        BLEND_VALID="true"
        
        # Extract EEVEE settings using Blender Python
        echo "Analyzing saved blend file..."
        cat > /tmp/analyze_eevee.py << 'ANALYSIS_EOF'
import bpy
import json
import sys

try:
    # Open the file passed as argument
    filepath = sys.argv[sys.argv.index("--") + 1]
    bpy.ops.wm.open_mainfile(filepath=filepath)
    
    scene = bpy.context.scene
    eevee = scene.eevee
    
    # Handle version differences for Raytracing/SSR
    use_rt = False
    if hasattr(eevee, "use_raytracing"):
        use_rt = eevee.use_raytracing
    elif hasattr(eevee, "use_ssr"):
        use_rt = eevee.use_ssr

    data = {
        "engine": scene.render.engine,
        "render_samples": getattr(eevee, "taa_render_samples", 0),
        "viewport_samples": getattr(eevee, "taa_samples", 0),
        "use_ao": getattr(eevee, "use_gtao", False),
        "ao_distance": getattr(eevee, "gtao_distance", 0.0),
        "use_raytracing": use_rt,
        "resolution_x": scene.render.resolution_x,
        "resolution_y": scene.render.resolution_y,
        "resolution_percentage": scene.render.resolution_percentage
    }
    
    print("ANALYSIS_JSON:" + json.dumps(data))
except Exception as e:
    print(f"Error analyzing file: {e}")
    print("ANALYSIS_JSON:{}")
ANALYSIS_EOF

        # Run analysis
        ANALYSIS_OUT=$(/opt/blender/blender --background --python /tmp/analyze_eevee.py -- "$BLEND_FILE" 2>&1)
        
        # Parse output
        SCENE_DATA=$(echo "$ANALYSIS_OUT" | grep "ANALYSIS_JSON:" | sed 's/ANALYSIS_JSON://')
        if [ -z "$SCENE_DATA" ]; then SCENE_DATA="{}"; fi
    fi
fi

# --- Create Result JSON ---
# Create temp file first to ensure atomic write/permission handling
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "render": {
        "exists": $RENDER_EXISTS,
        "size": $RENDER_SIZE,
        "width": $RENDER_WIDTH,
        "height": $RENDER_HEIGHT,
        "created_during_task": $RENDER_NEWER
    },
    "blend": {
        "exists": $BLEND_EXISTS,
        "valid": $BLEND_VALID,
        "saved_during_task": $BLEND_NEWER
    },
    "scene_settings": $SCENE_DATA
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" "$RESULT_FILE"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="