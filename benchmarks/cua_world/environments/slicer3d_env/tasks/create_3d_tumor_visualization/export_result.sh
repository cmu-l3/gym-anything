#!/bin/bash
echo "=== Exporting Create 3D Tumor Visualization Result ==="

source /workspace/scripts/task_utils.sh

# Get paths
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
EXPECTED_SCREENSHOT="$SCREENSHOT_DIR/tumor_3d_visualization.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot of application state
echo "Capturing final application state..."
take_screenshot /tmp/task_final.png ga
sleep 1

# ============================================================
# Check for expected screenshot file
# ============================================================
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_BYTES=0
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_MTIME=0

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_BYTES=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
        echo "Screenshot found and created during task"
    else
        echo "Screenshot found but existed before task"
    fi
    
    # Copy for verification
    cp "$EXPECTED_SCREENSHOT" /tmp/user_screenshot.png 2>/dev/null || true
else
    echo "Expected screenshot NOT found at: $EXPECTED_SCREENSHOT"
    
    # Look for any new screenshots
    echo "Searching for other screenshots..."
    INITIAL_COUNT=$(cat /tmp/initial_screenshot_count.txt 2>/dev/null || echo "0")
    CURRENT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
    
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
        # Get newest screenshot
        NEWEST=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -1)
        if [ -n "$NEWEST" ] && [ -f "$NEWEST" ]; then
            echo "Found new screenshot: $NEWEST"
            SCREENSHOT_EXISTS="true"
            SCREENSHOT_SIZE_BYTES=$(stat -c %s "$NEWEST" 2>/dev/null || echo "0")
            SCREENSHOT_MTIME=$(stat -c %Y "$NEWEST" 2>/dev/null || echo "0")
            if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
                SCREENSHOT_CREATED_DURING_TASK="true"
            fi
            cp "$NEWEST" /tmp/user_screenshot.png 2>/dev/null || true
        fi
    fi
fi

# ============================================================
# Query Slicer state via Python script
# ============================================================
SLICER_RUNNING="false"
SEGMENTATION_EXISTS="false"
VISIBILITY_3D_ENABLED="false"
THREED_VIEW_HAS_ACTORS="false"
NUM_ACTORS=0

if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running"
    
    # Create state query script
    cat > /tmp/query_slicer_state.py << 'PYEOF'
import slicer
import json

result = {
    "segmentation_exists": False,
    "segmentation_name": "",
    "visibility_3d_enabled": False,
    "visibility_2d_enabled": False,
    "threed_view_has_actors": False,
    "num_actors": 0,
    "volume_loaded": False,
    "volume_name": ""
}

# Check for segmentation
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
for seg_node in seg_nodes:
    if "Tumor" in seg_node.GetName():
        result["segmentation_exists"] = True
        result["segmentation_name"] = seg_node.GetName()
        
        display_node = seg_node.GetDisplayNode()
        if display_node:
            result["visibility_3d_enabled"] = display_node.GetVisibility3D()
            result["visibility_2d_enabled"] = display_node.GetVisibility2D()
        break

# Check 3D view for actors
try:
    layoutManager = slicer.app.layoutManager()
    threeDWidget = layoutManager.threeDWidget(0)
    if threeDWidget:
        threeDView = threeDWidget.threeDView()
        renderWindow = threeDView.renderWindow()
        renderers = renderWindow.GetRenderers()
        renderer = renderers.GetFirstRenderer()
        if renderer:
            actors = renderer.GetActors()
            result["num_actors"] = actors.GetNumberOfItems()
            result["threed_view_has_actors"] = actors.GetNumberOfItems() > 0
except Exception as e:
    print(f"Error checking 3D view: {e}")

# Check for loaded volumes
vol_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
if vol_nodes:
    result["volume_loaded"] = True
    result["volume_name"] = vol_nodes[0].GetName() if vol_nodes else ""

# Output as JSON
print("SLICER_STATE_JSON:" + json.dumps(result))
PYEOF

    # Run query script
    QUERY_OUTPUT=$(su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-code \"exec(open('/tmp/query_slicer_state.py').read())\" --no-main-window --no-splash 2>/dev/null" 2>&1 || echo "")
    
    # Parse output
    if echo "$QUERY_OUTPUT" | grep -q "SLICER_STATE_JSON:"; then
        STATE_JSON=$(echo "$QUERY_OUTPUT" | grep "SLICER_STATE_JSON:" | sed 's/SLICER_STATE_JSON://')
        
        SEGMENTATION_EXISTS=$(echo "$STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('segmentation_exists') else 'false')" 2>/dev/null || echo "false")
        VISIBILITY_3D_ENABLED=$(echo "$STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('visibility_3d_enabled') else 'false')" 2>/dev/null || echo "false")
        THREED_VIEW_HAS_ACTORS=$(echo "$STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('threed_view_has_actors') else 'false')" 2>/dev/null || echo "false")
        NUM_ACTORS=$(echo "$STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('num_actors', 0))" 2>/dev/null || echo "0")
        
        echo "Segmentation exists: $SEGMENTATION_EXISTS"
        echo "3D visibility enabled: $VISIBILITY_3D_ENABLED"
        echo "3D view has actors: $THREED_VIEW_HAS_ACTORS ($NUM_ACTORS)"
    else
        echo "Could not query Slicer state"
    fi
else
    echo "3D Slicer is NOT running"
fi

# ============================================================
# Analyze screenshot content (if exists)
# ============================================================
SCREENSHOT_HAS_3D_CONTENT="false"
SCREENSHOT_COLOR_COUNT=0

if [ -f /tmp/user_screenshot.png ]; then
    echo "Analyzing screenshot content..."
    
    # Check file size (3D renders are typically larger)
    SIZE_KB=$((SCREENSHOT_SIZE_BYTES / 1024))
    if [ "$SIZE_KB" -gt 50 ]; then
        SCREENSHOT_HAS_3D_CONTENT="true"
    fi
    
    # Count unique colors using Python/PIL
    SCREENSHOT_COLOR_COUNT=$(python3 << 'PYEOF'
try:
    from PIL import Image
    img = Image.open("/tmp/user_screenshot.png")
    # Sample for large images
    if img.width * img.height > 100000:
        img = img.resize((200, 200))
    colors = len(set(img.getdata()))
    print(colors)
except Exception as e:
    print(0)
PYEOF
)
    
    if [ "$SCREENSHOT_COLOR_COUNT" -gt 500 ]; then
        SCREENSHOT_HAS_3D_CONTENT="true"
    fi
    
    echo "Screenshot size: ${SIZE_KB}KB, colors: $SCREENSHOT_COLOR_COUNT"
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_running": $SLICER_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE_BYTES,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "screenshot_mtime": $SCREENSHOT_MTIME,
    "screenshot_has_3d_content": $SCREENSHOT_HAS_3D_CONTENT,
    "screenshot_color_count": $SCREENSHOT_COLOR_COUNT,
    "segmentation_exists": $SEGMENTATION_EXISTS,
    "visibility_3d_enabled": $VISIBILITY_3D_ENABLED,
    "threed_view_has_actors": $THREED_VIEW_HAS_ACTORS,
    "num_actors_in_3d": $NUM_ACTORS,
    "expected_screenshot_path": "$EXPECTED_SCREENSHOT",
    "final_screenshot_path": "/tmp/task_final.png",
    "user_screenshot_path": "/tmp/user_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/tumor_3d_task_result.json 2>/dev/null || sudo rm -f /tmp/tumor_3d_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/tumor_3d_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/tumor_3d_task_result.json
chmod 666 /tmp/tumor_3d_task_result.json 2>/dev/null || sudo chmod 666 /tmp/tumor_3d_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to /tmp/tumor_3d_task_result.json"
cat /tmp/tumor_3d_task_result.json
echo ""