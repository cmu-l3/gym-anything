#!/bin/bash
echo "=== Exporting Volume Rendering Bone Task Result ==="

source /workspace/scripts/task_utils.sh

SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
EXPECTED_SCREENSHOT="$SCREENSHOT_DIR/bone_rendering.png"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot of Slicer state
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
sleep 1

# ============================================================
# CHECK OUTPUT SCREENSHOT
# ============================================================
echo "Checking for bone_rendering.png..."

SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_BYTES=0
SCREENSHOT_SIZE_KB=0
SCREENSHOT_MTIME=0
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_WIDTH=0
SCREENSHOT_HEIGHT=0
SCREENSHOT_FORMAT="none"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_BYTES=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    SCREENSHOT_SIZE_KB=$((SCREENSHOT_SIZE_BYTES / 1024))
    SCREENSHOT_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Check if screenshot was created during task
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
        echo "Screenshot was created during task execution"
    else
        echo "WARNING: Screenshot exists but was NOT created during task"
    fi
    
    # Get image dimensions using Python/PIL
    IMAGE_INFO=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/SlicerData/Screenshots/bone_rendering.png")
    print(json.dumps({
        "width": img.width,
        "height": img.height,
        "format": img.format or "unknown",
        "mode": img.mode,
        "colors": len(set(list(img.resize((50, 50)).getdata())))
    }))
    img.close()
except Exception as e:
    print(json.dumps({"width": 0, "height": 0, "format": "error", "mode": "unknown", "colors": 0, "error": str(e)}))
PYEOF
)
    
    SCREENSHOT_WIDTH=$(echo "$IMAGE_INFO" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    SCREENSHOT_HEIGHT=$(echo "$IMAGE_INFO" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    SCREENSHOT_FORMAT=$(echo "$IMAGE_INFO" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    SCREENSHOT_COLORS=$(echo "$IMAGE_INFO" | python3 -c "import json, sys; print(json.load(sys.stdin).get('colors', 0))" 2>/dev/null || echo "0")
    
    echo "Screenshot found: ${SCREENSHOT_SIZE_KB}KB, ${SCREENSHOT_WIDTH}x${SCREENSHOT_HEIGHT}, ${SCREENSHOT_FORMAT}, ~${SCREENSHOT_COLORS} unique colors"
    
    # Copy to tmp for verification
    cp "$EXPECTED_SCREENSHOT" /tmp/bone_rendering_output.png 2>/dev/null || true
else
    echo "Screenshot NOT found at expected location"
    
    # Check if screenshot was saved elsewhere
    echo "Searching for potential screenshots..."
    ALTERNATE_SCREENSHOTS=$(find /home/ga -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | head -5)
    if [ -n "$ALTERNATE_SCREENSHOTS" ]; then
        echo "Found recent PNG files:"
        echo "$ALTERNATE_SCREENSHOTS"
    fi
fi

# ============================================================
# CHECK SLICER STATE
# ============================================================
echo "Checking 3D Slicer state..."

SLICER_RUNNING="false"
VOLUME_RENDERING_ACTIVE="false"
PRESET_NAME="none"
DATA_LOADED="false"

if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running"
    
    # Query Slicer's internal state via Python
    cat > /tmp/check_vr_state.py << 'PYEOF'
import json
import sys
sys.path.insert(0, '/opt/Slicer/lib/Python/lib/python3.9/site-packages')

result = {
    "volume_rendering_active": False,
    "preset_name": "none",
    "data_loaded": False,
    "volume_count": 0,
    "vr_display_nodes": 0
}

try:
    import slicer
    
    # Check for loaded volumes
    volume_nodes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    result['volume_count'] = volume_nodes.GetNumberOfItems() if volume_nodes else 0
    result['data_loaded'] = result['volume_count'] > 0
    
    # Check for volume rendering display nodes
    vr_nodes = slicer.util.getNodesByClass('vtkMRMLVolumeRenderingDisplayNode')
    if vr_nodes:
        result['vr_display_nodes'] = vr_nodes.GetNumberOfItems()
        for i in range(vr_nodes.GetNumberOfItems()):
            vr_node = vr_nodes.GetItemAsObject(i)
            if vr_node and vr_node.GetVisibility():
                result['volume_rendering_active'] = True
                # Try to get preset name
                prop_node = vr_node.GetVolumePropertyNode()
                if prop_node:
                    result['preset_name'] = prop_node.GetName() or "custom"
                break
    
except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
PYEOF
    
    # Run the check script
    SLICER_STATE=$(timeout 15 su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/check_vr_state.py --no-main-window 2>/dev/null" 2>/dev/null || echo '{}')
    
    # Parse the result
    if [ -n "$SLICER_STATE" ] && echo "$SLICER_STATE" | grep -q "{"; then
        VOLUME_RENDERING_ACTIVE=$(echo "$SLICER_STATE" | python3 -c "import json, sys; print('true' if json.load(sys.stdin).get('volume_rendering_active', False) else 'false')" 2>/dev/null || echo "false")
        PRESET_NAME=$(echo "$SLICER_STATE" | python3 -c "import json, sys; print(json.load(sys.stdin).get('preset_name', 'none'))" 2>/dev/null || echo "none")
        DATA_LOADED=$(echo "$SLICER_STATE" | python3 -c "import json, sys; print('true' if json.load(sys.stdin).get('data_loaded', False) else 'false')" 2>/dev/null || echo "false")
        
        echo "Volume rendering active: $VOLUME_RENDERING_ACTIVE"
        echo "Preset name: $PRESET_NAME"
        echo "Data loaded: $DATA_LOADED"
    else
        echo "Could not query Slicer state directly"
        # Fall back to heuristics
        DATA_LOADED="true"  # Assume data was loaded if Slicer started with file
    fi
else
    echo "3D Slicer is NOT running"
fi

# ============================================================
# CHECK WINDOW TITLES FOR EVIDENCE
# ============================================================
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
VOLUME_RENDERING_MODULE_ACCESSED="false"

if echo "$WINDOW_LIST" | grep -qi "Volume Rendering\|VolumeRendering"; then
    VOLUME_RENDERING_MODULE_ACCESSED="true"
    echo "Volume Rendering module appears to have been accessed"
fi

# ============================================================
# CREATE RESULT JSON
# ============================================================
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE_BYTES,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_mtime": $SCREENSHOT_MTIME,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "screenshot_width": $SCREENSHOT_WIDTH,
    "screenshot_height": $SCREENSHOT_HEIGHT,
    "screenshot_format": "$SCREENSHOT_FORMAT",
    "screenshot_colors": ${SCREENSHOT_COLORS:-0},
    "slicer_was_running": $SLICER_RUNNING,
    "volume_rendering_active": $VOLUME_RENDERING_ACTIVE,
    "preset_name": "$PRESET_NAME",
    "data_loaded": $DATA_LOADED,
    "volume_rendering_module_accessed": $VOLUME_RENDERING_MODULE_ACCESSED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="