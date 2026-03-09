#!/bin/bash
echo "=== Exporting Liver Volume Rendering Task Results ==="

source /workspace/scripts/task_utils.sh

EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
EXPECTED_OUTPUT="$EXPORTS_DIR/liver_volume_rendering.png"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot of Slicer state
echo "Capturing final screenshot..."
take_screenshot /tmp/liver_vr_final.png ga
sleep 1

# ============================================================
# CHECK OUTPUT FILE
# ============================================================
echo "Checking for expected output file..."

OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_OUTPUT" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    
    echo "Output file found: $EXPECTED_OUTPUT"
    echo "  Size: $OUTPUT_SIZE bytes ($((OUTPUT_SIZE / 1024)) KB)"
    echo "  Modified: $(date -d @$OUTPUT_MTIME)"
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "  Status: Created during task"
    else
        echo "  Status: Existed before task (not modified)"
    fi
    
    # Copy to temp for verification
    cp "$EXPECTED_OUTPUT" /tmp/liver_vr_output.png 2>/dev/null || true
else
    echo "Output file NOT found at: $EXPECTED_OUTPUT"
    
    # Search for any recent screenshots
    echo "Searching for recent screenshots..."
    RECENT_SCREENSHOTS=$(find /home/ga -name "*.png" -newer /tmp/task_start_time.txt -type f 2>/dev/null | head -5)
    if [ -n "$RECENT_SCREENSHOTS" ]; then
        echo "Found recent screenshots:"
        echo "$RECENT_SCREENSHOTS"
        
        # Use the most recent one as potential output
        NEWEST=$(echo "$RECENT_SCREENSHOTS" | head -1)
        if [ -f "$NEWEST" ]; then
            cp "$NEWEST" /tmp/liver_vr_output.png 2>/dev/null || true
            echo "Using $NEWEST as potential output"
        fi
    fi
fi

# ============================================================
# CHECK SLICER STATE
# ============================================================
echo ""
echo "Checking Slicer state..."

SLICER_RUNNING="false"
VR_ENABLED="false"
VR_VOLUME_NAME=""
TF_POINTS=0
VOLUME_COUNT=0

if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Query Slicer state via Python
    cat > /tmp/query_vr_state.py << 'PYEOF'
import slicer
import json
import sys

result = {
    "vr_enabled": False,
    "vr_volume_name": "",
    "tf_points": 0,
    "volume_count": 0,
    "vr_preset": "",
    "window_level": []
}

try:
    # Count volumes
    volumes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    result['volume_count'] = len(volumes)
    
    # Check volume rendering
    vrLogic = slicer.modules.volumerendering.logic()
    
    for vol in volumes:
        vrNode = vrLogic.GetFirstVolumeRenderingDisplayNode(vol)
        if vrNode and vrNode.GetVisibility():
            result['vr_enabled'] = True
            result['vr_volume_name'] = vol.GetName()
            
            # Check transfer function
            propNode = vrNode.GetVolumePropertyNode()
            if propNode:
                prop = propNode.GetVolumeProperty()
                if prop:
                    opacity = prop.GetScalarOpacity()
                    if opacity:
                        result['tf_points'] = opacity.GetSize()
                    
                    # Get preset name if available
                    if hasattr(propNode, 'GetName'):
                        result['vr_preset'] = propNode.GetName()
            break
    
    # Get window/level
    for vol in volumes:
        displayNode = vol.GetDisplayNode()
        if displayNode:
            result['window_level'] = [displayNode.GetWindow(), displayNode.GetLevel()]
            break

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
PYEOF

    SLICER_STATE=$(sudo -u ga DISPLAY=:1 timeout 30 /opt/Slicer/Slicer --no-splash --no-main-window --python-script /tmp/query_vr_state.py 2>/dev/null | tail -1)
    
    if [ -n "$SLICER_STATE" ] && echo "$SLICER_STATE" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        echo "Slicer state query result: $SLICER_STATE"
        
        VR_ENABLED=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('vr_enabled', False) else 'false')" 2>/dev/null || echo "false")
        VR_VOLUME_NAME=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('vr_volume_name', ''))" 2>/dev/null || echo "")
        TF_POINTS=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tf_points', 0))" 2>/dev/null || echo "0")
        VOLUME_COUNT=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('volume_count', 0))" 2>/dev/null || echo "0")
        VR_PRESET=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('vr_preset', ''))" 2>/dev/null || echo "")
    else
        echo "Could not parse Slicer state query result"
    fi
else
    echo "Slicer is NOT running"
fi

echo ""
echo "Volume rendering enabled: $VR_ENABLED"
echo "Volume name: $VR_VOLUME_NAME"
echo "Transfer function points: $TF_POINTS"
echo "Volume count: $VOLUME_COUNT"

# ============================================================
# CHECK SCREENSHOT QUALITY
# ============================================================
SCREENSHOT_HAS_CONTENT="false"
SCREENSHOT_COLOR_COUNT=0

SCREENSHOT_TO_CHECK=""
if [ -f "$EXPECTED_OUTPUT" ]; then
    SCREENSHOT_TO_CHECK="$EXPECTED_OUTPUT"
elif [ -f /tmp/liver_vr_output.png ]; then
    SCREENSHOT_TO_CHECK="/tmp/liver_vr_output.png"
elif [ -f /tmp/liver_vr_final.png ]; then
    SCREENSHOT_TO_CHECK="/tmp/liver_vr_final.png"
fi

if [ -n "$SCREENSHOT_TO_CHECK" ] && [ -f "$SCREENSHOT_TO_CHECK" ]; then
    echo ""
    echo "Analyzing screenshot: $SCREENSHOT_TO_CHECK"
    
    # Check file size
    SCREENSHOT_SIZE_KB=$(($(stat -c%s "$SCREENSHOT_TO_CHECK" 2>/dev/null || echo "0") / 1024))
    echo "  Size: ${SCREENSHOT_SIZE_KB} KB"
    
    # Count unique colors using Python/PIL
    SCREENSHOT_COLOR_COUNT=$(python3 << PYEOF
try:
    from PIL import Image
    img = Image.open("$SCREENSHOT_TO_CHECK")
    # Sample for large images
    if img.width * img.height > 100000:
        img = img.resize((200, 200))
    colors = len(set(img.getdata()))
    print(colors)
except Exception as e:
    print(0)
PYEOF
)
    echo "  Unique colors: $SCREENSHOT_COLOR_COUNT"
    
    # Determine if screenshot has meaningful content
    if [ "$SCREENSHOT_SIZE_KB" -gt 100 ] && [ "$SCREENSHOT_COLOR_COUNT" -gt 500 ]; then
        SCREENSHOT_HAS_CONTENT="true"
        echo "  Assessment: Has significant content"
    elif [ "$SCREENSHOT_SIZE_KB" -gt 50 ] && [ "$SCREENSHOT_COLOR_COUNT" -gt 100 ]; then
        SCREENSHOT_HAS_CONTENT="partial"
        echo "  Assessment: Has some content"
    else
        echo "  Assessment: May be blank or minimal content"
    fi
fi

# ============================================================
# CREATE RESULT JSON
# ============================================================
echo ""
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_size_kb": $((OUTPUT_SIZE / 1024)),
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "slicer_was_running": $SLICER_RUNNING,
    "vr_enabled": $VR_ENABLED,
    "vr_volume_name": "$VR_VOLUME_NAME",
    "tf_points": $TF_POINTS,
    "volume_count": $VOLUME_COUNT,
    "screenshot_has_content": "$SCREENSHOT_HAS_CONTENT",
    "screenshot_color_count": $SCREENSHOT_COLOR_COUNT,
    "expected_output_path": "$EXPECTED_OUTPUT",
    "final_screenshot": "/tmp/liver_vr_final.png",
    "output_screenshot": "/tmp/liver_vr_output.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/liver_vr_task_result.json 2>/dev/null || sudo rm -f /tmp/liver_vr_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/liver_vr_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/liver_vr_task_result.json
chmod 666 /tmp/liver_vr_task_result.json 2>/dev/null || sudo chmod 666 /tmp/liver_vr_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/liver_vr_task_result.json"
cat /tmp/liver_vr_task_result.json
echo ""
echo "=== Export Complete ==="