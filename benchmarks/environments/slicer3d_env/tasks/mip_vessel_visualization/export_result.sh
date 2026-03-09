#!/bin/bash
echo "=== Exporting MIP Vessel Visualization Result ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MIP="$AMOS_DIR/aorta_mip.png"
OUTPUT_PARAMS="$AMOS_DIR/mip_parameters.json"

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task timing: start=$TASK_START, end=$TASK_END"

# Take final screenshot
echo "Capturing final state..."
take_screenshot /tmp/mip_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# ================================================================
# CHECK FOR MIP IMAGE
# ================================================================
MIP_EXISTS="false"
MIP_SIZE=0
MIP_TIMESTAMP=0
MIP_CREATED_DURING_TASK="false"
MIP_PATH=""

# Check multiple possible locations for the MIP image
POSSIBLE_MIP_PATHS=(
    "$OUTPUT_MIP"
    "$AMOS_DIR/mip.png"
    "$AMOS_DIR/aorta_mip.PNG"
    "$AMOS_DIR/vessel_mip.png"
    "$AMOS_DIR/screenshot.png"
    "/home/ga/Documents/aorta_mip.png"
    "/home/ga/aorta_mip.png"
)

for path in "${POSSIBLE_MIP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MIP_EXISTS="true"
        MIP_PATH="$path"
        MIP_SIZE=$(stat -c%s "$path" 2>/dev/null || echo "0")
        MIP_TIMESTAMP=$(stat -c%Y "$path" 2>/dev/null || echo "0")
        
        # Check if created during task
        if [ "$MIP_TIMESTAMP" -gt "$TASK_START" ]; then
            MIP_CREATED_DURING_TASK="true"
        fi
        
        echo "Found MIP image at: $path (size: $MIP_SIZE bytes)"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MIP" ]; then
            cp "$path" "$OUTPUT_MIP" 2>/dev/null || true
            echo "Copied to: $OUTPUT_MIP"
        fi
        break
    fi
done

# ================================================================
# CHECK FOR PARAMETERS FILE
# ================================================================
PARAMS_EXISTS="false"
PARAMS_PATH=""
WINDOW_WIDTH=0
WINDOW_LEVEL=0
SLAB_THICKNESS=0
PROJECTION=""
RENDERING_MODE=""

POSSIBLE_PARAMS_PATHS=(
    "$OUTPUT_PARAMS"
    "$AMOS_DIR/mip_parameters.json"
    "$AMOS_DIR/parameters.json"
    "$AMOS_DIR/params.json"
    "/home/ga/Documents/mip_parameters.json"
    "/home/ga/mip_parameters.json"
)

for path in "${POSSIBLE_PARAMS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        PARAMS_EXISTS="true"
        PARAMS_PATH="$path"
        echo "Found parameters file at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_PARAMS" ]; then
            cp "$path" "$OUTPUT_PARAMS" 2>/dev/null || true
        fi
        
        # Parse parameters
        WINDOW_WIDTH=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    val = d.get('window_width', d.get('window', d.get('Window', 0)))
    print(int(float(val)) if val else 0)
except:
    print(0)
" 2>/dev/null || echo "0")
        
        WINDOW_LEVEL=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    val = d.get('window_level', d.get('level', d.get('Level', 0)))
    print(int(float(val)) if val else 0)
except:
    print(0)
" 2>/dev/null || echo "0")
        
        SLAB_THICKNESS=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    val = d.get('slab_thickness', d.get('thickness', d.get('SlabThickness', 0)))
    print(int(float(val)) if val else 0)
except:
    print(0)
" 2>/dev/null || echo "0")
        
        PROJECTION=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    print(d.get('projection', d.get('view', '')))
except:
    print('')
" 2>/dev/null || echo "")
        
        RENDERING_MODE=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    print(d.get('rendering_mode', d.get('mode', d.get('type', ''))))
except:
    print('')
" 2>/dev/null || echo "")
        
        echo "Parsed parameters: W=$WINDOW_WIDTH, L=$WINDOW_LEVEL, Slab=$SLAB_THICKNESS, Proj=$PROJECTION, Mode=$RENDERING_MODE"
        break
    fi
done

# ================================================================
# GET IMAGE INFO IF EXISTS
# ================================================================
IMAGE_WIDTH=0
IMAGE_HEIGHT=0
IMAGE_FORMAT="none"

if [ "$MIP_EXISTS" = "true" ] && [ -f "$OUTPUT_MIP" ]; then
    IMAGE_INFO=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/SlicerData/AMOS/aorta_mip.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "PNG", "mode": img.mode}))
    img.close()
except Exception as e:
    print(json.dumps({"width": 0, "height": 0, "format": "error", "error": str(e)}))
PYEOF
)
    
    IMAGE_WIDTH=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    
    echo "Image info: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}, format=$IMAGE_FORMAT"
fi

# ================================================================
# COPY FILES FOR VERIFICATION
# ================================================================
echo "Copying files for verification..."

# Copy MIP image to /tmp for verifier
if [ -f "$OUTPUT_MIP" ]; then
    cp "$OUTPUT_MIP" /tmp/aorta_mip.png 2>/dev/null || true
    chmod 644 /tmp/aorta_mip.png 2>/dev/null || true
fi

# Copy parameters file to /tmp for verifier
if [ -f "$OUTPUT_PARAMS" ]; then
    cp "$OUTPUT_PARAMS" /tmp/mip_parameters.json 2>/dev/null || true
    chmod 644 /tmp/mip_parameters.json 2>/dev/null || true
fi

# Copy final screenshot
if [ -f /tmp/mip_final.png ]; then
    chmod 644 /tmp/mip_final.png 2>/dev/null || true
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "mip_image_exists": $MIP_EXISTS,
    "mip_image_path": "$MIP_PATH",
    "mip_image_size_bytes": $MIP_SIZE,
    "mip_timestamp": $MIP_TIMESTAMP,
    "mip_created_during_task": $MIP_CREATED_DURING_TASK,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "params_file_exists": $PARAMS_EXISTS,
    "params_path": "$PARAMS_PATH",
    "window_width": $WINDOW_WIDTH,
    "window_level": $WINDOW_LEVEL,
    "slab_thickness": $SLAB_THICKNESS,
    "projection": "$PROJECTION",
    "rendering_mode": "$RENDERING_MODE",
    "final_screenshot_exists": $([ -f "/tmp/mip_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/mip_task_result.json 2>/dev/null || sudo rm -f /tmp/mip_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/mip_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/mip_task_result.json
chmod 666 /tmp/mip_task_result.json 2>/dev/null || sudo chmod 666 /tmp/mip_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/mip_task_result.json
echo ""
echo "=== Export Complete ==="