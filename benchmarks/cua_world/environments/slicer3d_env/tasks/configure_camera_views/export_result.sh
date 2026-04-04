#!/bin/bash
echo "=== Exporting Configure Camera Views Result ==="

source /workspace/scripts/task_utils.sh

# Get timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define paths
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
ANTERIOR_FILE="$SCREENSHOT_DIR/anterior_view.png"
LATERAL_FILE="$SCREENSHOT_DIR/lateral_view.png"
SUPERIOR_FILE="$SCREENSHOT_DIR/superior_view.png"

# Take final screenshot of application state
echo "Capturing final application state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if Slicer is still running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Function to check screenshot file
check_screenshot() {
    local filepath="$1"
    local name="$2"
    
    local exists="false"
    local size_kb=0
    local mtime=0
    local created_during_task="false"
    local width=0
    local height=0
    
    if [ -f "$filepath" ]; then
        exists="true"
        size_kb=$(du -k "$filepath" 2>/dev/null | cut -f1 || echo "0")
        mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        
        # Check if created during task
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        
        # Get image dimensions using Python/PIL
        DIMS=$(python3 << PYEOF
try:
    from PIL import Image
    img = Image.open("$filepath")
    print(f"{img.width} {img.height}")
except Exception as e:
    print("0 0")
PYEOF
)
        width=$(echo "$DIMS" | cut -d' ' -f1)
        height=$(echo "$DIMS" | cut -d' ' -f2)
    fi
    
    echo "{\"exists\": $exists, \"size_kb\": $size_kb, \"mtime\": $mtime, \"created_during_task\": $created_during_task, \"width\": $width, \"height\": $height}"
}

echo "Checking screenshot files..."

# Check each screenshot
ANTERIOR_INFO=$(check_screenshot "$ANTERIOR_FILE" "anterior")
LATERAL_INFO=$(check_screenshot "$LATERAL_FILE" "lateral")
SUPERIOR_INFO=$(check_screenshot "$SUPERIOR_FILE" "superior")

echo "Anterior: $ANTERIOR_INFO"
echo "Lateral: $LATERAL_INFO"
echo "Superior: $SUPERIOR_INFO"

# Count total screenshots created during task
SCREENSHOTS_CREATED=0
[ "$(echo "$ANTERIOR_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('created_during_task', False))" 2>/dev/null)" = "True" ] && SCREENSHOTS_CREATED=$((SCREENSHOTS_CREATED + 1))
[ "$(echo "$LATERAL_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('created_during_task', False))" 2>/dev/null)" = "True" ] && SCREENSHOTS_CREATED=$((SCREENSHOTS_CREATED + 1))
[ "$(echo "$SUPERIOR_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('created_during_task', False))" 2>/dev/null)" = "True" ] && SCREENSHOTS_CREATED=$((SCREENSHOTS_CREATED + 1))

echo "Screenshots created during task: $SCREENSHOTS_CREATED"

# Check for volume rendering in Slicer
VOLUME_RENDERING_ENABLED="false"
if [ "$SLICER_RUNNING" = "true" ]; then
    # Try to query Slicer state via Python
    cat > /tmp/check_vr.py << 'PYEOF'
import slicer
import json

result = {
    "volume_rendering_enabled": False,
    "volumes_loaded": 0,
    "vr_display_nodes": 0
}

try:
    # Count loaded volumes
    volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    result["volumes_loaded"] = volumes.GetNumberOfItems()
    
    # Check for volume rendering display nodes
    vr_nodes = slicer.util.getNodesByClass("vtkMRMLVolumeRenderingDisplayNode")
    result["vr_display_nodes"] = vr_nodes.GetNumberOfItems()
    
    # Check if any VR node is visible
    for i in range(vr_nodes.GetNumberOfItems()):
        node = vr_nodes.GetItemAsObject(i)
        if node and node.GetVisibility():
            result["volume_rendering_enabled"] = True
            break

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    VR_CHECK=$(sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/check_vr.py --no-main-window 2>/dev/null | tail -1)
    
    if echo "$VR_CHECK" | grep -q "volume_rendering_enabled"; then
        VOLUME_RENDERING_ENABLED=$(echo "$VR_CHECK" | python3 -c "import sys,json; print('true' if json.load(sys.stdin).get('volume_rendering_enabled', False) else 'false')" 2>/dev/null || echo "false")
        VOLUMES_LOADED=$(echo "$VR_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin).get('volumes_loaded', 0))" 2>/dev/null || echo "0")
        VR_NODES=$(echo "$VR_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin).get('vr_display_nodes', 0))" 2>/dev/null || echo "0")
    fi
fi

# Copy screenshots to /tmp for verification (in case permissions issue)
cp "$ANTERIOR_FILE" /tmp/anterior_view.png 2>/dev/null || true
cp "$LATERAL_FILE" /tmp/lateral_view.png 2>/dev/null || true
cp "$SUPERIOR_FILE" /tmp/superior_view.png 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_running": $SLICER_RUNNING,
    "volume_rendering_enabled": ${VOLUME_RENDERING_ENABLED:-false},
    "volumes_loaded": ${VOLUMES_LOADED:-0},
    "vr_display_nodes": ${VR_NODES:-0},
    "screenshots_created_count": $SCREENSHOTS_CREATED,
    "anterior": $ANTERIOR_INFO,
    "lateral": $LATERAL_INFO,
    "superior": $SUPERIOR_INFO,
    "screenshot_dir": "$SCREENSHOT_DIR",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/camera_views_result.json 2>/dev/null || sudo rm -f /tmp/camera_views_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/camera_views_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/camera_views_result.json
chmod 666 /tmp/camera_views_result.json 2>/dev/null || sudo chmod 666 /tmp/camera_views_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/camera_views_result.json"
cat /tmp/camera_views_result.json
echo ""
echo "=== Export Complete ==="