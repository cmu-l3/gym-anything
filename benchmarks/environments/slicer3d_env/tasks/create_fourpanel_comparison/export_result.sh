#!/bin/bash
echo "=== Exporting Four-Panel Comparison Result ==="

source /workspace/scripts/task_utils.sh

# Get sample ID
if [ -f /tmp/task_sample_id.txt ]; then
    SAMPLE_ID=$(cat /tmp/task_sample_id.txt)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
EXPECTED_SCREENSHOT="$SCREENSHOT_DIR/four_panel_comparison.png"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot of current state
echo "Capturing final state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    FINAL_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SIZE} bytes"
fi

# ================================================================
# Check for the expected screenshot file
# ================================================================
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
SCREENSHOT_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k "$EXPECTED_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Found expected screenshot: $EXPECTED_SCREENSHOT"
    echo "  Size: ${SCREENSHOT_SIZE_KB}KB"
    echo "  Created during task: $FILE_CREATED_DURING_TASK"
    
    # Copy for verification
    cp "$EXPECTED_SCREENSHOT" /tmp/four_panel_screenshot.png 2>/dev/null || true
fi

# Also check for any new screenshots in the directory
INITIAL_COUNT=$(cat /tmp/initial_screenshot_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
NEW_SCREENSHOTS=$((FINAL_COUNT - INITIAL_COUNT))

# Get the newest screenshot if agent saved with different name
NEWEST_SCREENSHOT=""
if [ "$NEW_SCREENSHOTS" -gt 0 ]; then
    NEWEST_SCREENSHOT=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -1)
    if [ -n "$NEWEST_SCREENSHOT" ] && [ "$NEWEST_SCREENSHOT" != "$EXPECTED_SCREENSHOT" ]; then
        echo "Found newest screenshot: $NEWEST_SCREENSHOT"
        # Copy for backup verification
        cp "$NEWEST_SCREENSHOT" /tmp/four_panel_screenshot_alt.png 2>/dev/null || true
    fi
fi

# ================================================================
# Check Slicer state
# ================================================================
SLICER_RUNNING="false"
CURRENT_LAYOUT=""
VOLUMES_LOADED=0
SLICE_VIEWS_COUNT=0

if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    
    # Try to query Slicer state
    QUERY_SCRIPT="/tmp/query_slicer_state.py"
    cat > "$QUERY_SCRIPT" << 'PYEOF'
import slicer
import json

result = {}

# Get layout
lm = slicer.app.layoutManager()
if lm:
    result["layout_id"] = lm.layout
    # FourUp layout is typically 6 or similar
    layout_names = {
        1: "Conventional",
        2: "FourUp",
        3: "OneUp3D",
        4: "OneUpRedSlice",
        6: "FourUpPlot",
        7: "Tabbed3D",
        21: "TwoOverTwo",
    }
    result["layout_name"] = layout_names.get(lm.layout, f"Layout_{lm.layout}")

# Get volumes
volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
result["volume_count"] = volumes.GetNumberOfItems()
result["volume_names"] = [volumes.GetItemAsObject(i).GetName() for i in range(volumes.GetNumberOfItems())]

# Get slice views
slice_nodes = slicer.util.getNodesByClass("vtkMRMLSliceNode")
result["slice_view_count"] = slice_nodes.GetNumberOfItems()

# Check linked status
linked = True
for i in range(slice_nodes.GetNumberOfItems()):
    node = slice_nodes.GetItemAsObject(i)
    if not node.GetLinkedControl():
        linked = False
        break
result["views_linked"] = linked

# Get current slice offset (to check if navigated to tumor region)
red_node = slicer.mrmlScene.GetNodeByID("vtkMRMLSliceNodeRed")
if red_node:
    result["red_slice_offset"] = red_node.GetSliceOffset()

# Output as JSON
print("SLICER_STATE_JSON=" + json.dumps(result))
PYEOF

    chmod 644 "$QUERY_SCRIPT"
    
    # Run query with timeout
    timeout 10 su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script '$QUERY_SCRIPT' --no-main-window" > /tmp/slicer_state.log 2>&1 || true
    
    if [ -f /tmp/slicer_state.log ]; then
        STATE_LINE=$(grep "SLICER_STATE_JSON=" /tmp/slicer_state.log | head -1)
        if [ -n "$STATE_LINE" ]; then
            STATE_JSON=$(echo "$STATE_LINE" | sed 's/SLICER_STATE_JSON=//')
            echo "Slicer state: $STATE_JSON"
            
            CURRENT_LAYOUT=$(echo "$STATE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('layout_name', ''))" 2>/dev/null || echo "")
            VOLUMES_LOADED=$(echo "$STATE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('volume_count', 0))" 2>/dev/null || echo "0")
            SLICE_VIEWS_COUNT=$(echo "$STATE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('slice_view_count', 0))" 2>/dev/null || echo "0")
        fi
    fi
fi

# ================================================================
# Analyze screenshot image properties
# ================================================================
IMAGE_WIDTH=0
IMAGE_HEIGHT=0
IMAGE_COLORS=0

SCREENSHOT_TO_ANALYZE=""
if [ -f /tmp/four_panel_screenshot.png ]; then
    SCREENSHOT_TO_ANALYZE="/tmp/four_panel_screenshot.png"
elif [ -f /tmp/four_panel_screenshot_alt.png ]; then
    SCREENSHOT_TO_ANALYZE="/tmp/four_panel_screenshot_alt.png"
elif [ -f /tmp/task_final.png ]; then
    SCREENSHOT_TO_ANALYZE="/tmp/task_final.png"
fi

if [ -n "$SCREENSHOT_TO_ANALYZE" ]; then
    # Use Python PIL to analyze
    python3 << PYEOF
import json
try:
    from PIL import Image
    img = Image.open("$SCREENSHOT_TO_ANALYZE")
    # Count unique colors (sample for speed)
    img_small = img.resize((200, 200))
    colors = len(set(img_small.getdata()))
    print(f"IMAGE_WIDTH={img.width}")
    print(f"IMAGE_HEIGHT={img.height}")
    print(f"IMAGE_COLORS={colors}")
except Exception as e:
    print(f"IMAGE_ERROR={e}")
PYEOF
    
    IMAGE_WIDTH=$(grep "IMAGE_WIDTH=" /dev/stdin 2>/dev/null | cut -d'=' -f2 || echo "0")
    IMAGE_HEIGHT=$(grep "IMAGE_HEIGHT=" /dev/stdin 2>/dev/null | cut -d'=' -f2 || echo "0")
    IMAGE_COLORS=$(grep "IMAGE_COLORS=" /dev/stdin 2>/dev/null | cut -d'=' -f2 || echo "0")
    
    # Re-run to capture output
    IMAGE_INFO=$(python3 << PYEOF
import json
try:
    from PIL import Image
    img = Image.open("$SCREENSHOT_TO_ANALYZE")
    img_small = img.resize((200, 200))
    colors = len(set(img_small.getdata()))
    print(json.dumps({"width": img.width, "height": img.height, "colors": colors}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)
    
    if [ -n "$IMAGE_INFO" ]; then
        IMAGE_WIDTH=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
        IMAGE_HEIGHT=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
        IMAGE_COLORS=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('colors', 0))" 2>/dev/null || echo "0")
    fi
fi

echo ""
echo "Image analysis: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}, ${IMAGE_COLORS} colors"

# ================================================================
# Create result JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sample_id": "$SAMPLE_ID",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "new_screenshots_count": $NEW_SCREENSHOTS,
    "slicer_was_running": $SLICER_RUNNING,
    "current_layout": "$CURRENT_LAYOUT",
    "volumes_loaded": $VOLUMES_LOADED,
    "slice_views_count": $SLICE_VIEWS_COUNT,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_colors": $IMAGE_COLORS,
    "expected_screenshot_path": "$EXPECTED_SCREENSHOT",
    "screenshot_to_verify": "$SCREENSHOT_TO_ANALYZE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/fourpanel_task_result.json 2>/dev/null || sudo rm -f /tmp/fourpanel_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fourpanel_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fourpanel_task_result.json
chmod 666 /tmp/fourpanel_task_result.json 2>/dev/null || sudo chmod 666 /tmp/fourpanel_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/fourpanel_task_result.json"
cat /tmp/fourpanel_task_result.json
echo ""
echo "=== Export Complete ==="