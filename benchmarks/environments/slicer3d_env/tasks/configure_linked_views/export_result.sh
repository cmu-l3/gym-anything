#!/bin/bash
echo "=== Exporting Configure Linked Views Result ==="

source /workspace/scripts/task_utils.sh

EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
EXPECTED_SCREENSHOT="$EXPORTS_DIR/linked_views.png"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Query Slicer state via Python script
SLICER_STATE_SCRIPT="/tmp/query_slicer_state.py"
cat > "$SLICER_STATE_SCRIPT" << 'PYEOF'
import slicer
import json
import os

result = {
    "layout_id": -1,
    "layout_name": "",
    "num_slice_views": 0,
    "slice_views": {},
    "volumes_loaded": [],
    "red_volume_id": "",
    "yellow_volume_id": "",
    "green_volume_id": "",
    "red_volume_name": "",
    "yellow_volume_name": "",
    "green_volume_name": "",
    "linking_enabled_red": False,
    "linking_enabled_yellow": False,
    "linking_enabled_green": False,
    "red_slice_offset": 0.0,
    "yellow_slice_offset": 0.0,
    "green_slice_offset": 0.0,
    "different_volumes_displayed": False,
    "offsets_synchronized": False
}

try:
    lm = slicer.app.layoutManager()
    
    # Get current layout
    result["layout_id"] = lm.layout
    
    # Map layout IDs to names
    layout_names = {
        1: "FourUp",
        2: "Conventional",
        3: "OneUp3D",
        4: "OneUpRedSlice",
        5: "OneUpYellowSlice",
        6: "OneUpGreenSlice",
        12: "CompareWidescreenAxial",
        13: "CompareWidescreenSagittal",
        14: "CompareWidescreenCoronal",
        15: "Compare",
        23: "TwoOverTwo",
        24: "SideBySide",
        25: "FourOver",
        26: "ConventionalWidescreen"
    }
    result["layout_name"] = layout_names.get(result["layout_id"], f"Layout_{result['layout_id']}")
    
    # Count active slice views
    for color in ['Red', 'Yellow', 'Green']:
        try:
            widget = lm.sliceWidget(color)
            if widget and widget.isVisible():
                result["num_slice_views"] += 1
                
                # Get slice logic and nodes
                slice_logic = widget.sliceLogic()
                composite_node = slice_logic.GetSliceCompositeNode()
                slice_node = slice_logic.GetSliceNode()
                
                # Get volume IDs
                bg_vol_id = composite_node.GetBackgroundVolumeID() or ""
                
                # Get volume name
                bg_vol_name = ""
                if bg_vol_id:
                    vol_node = slicer.mrmlScene.GetNodeByID(bg_vol_id)
                    if vol_node:
                        bg_vol_name = vol_node.GetName()
                
                # Get linking state
                linked = slice_node.GetLinkedControl() if slice_node else False
                
                # Get slice offset
                offset = slice_node.GetSliceOffset() if slice_node else 0.0
                
                result["slice_views"][color] = {
                    "visible": True,
                    "volume_id": bg_vol_id,
                    "volume_name": bg_vol_name,
                    "linked": linked,
                    "slice_offset": offset
                }
                
                # Store individual fields for easier access
                result[f"{color.lower()}_volume_id"] = bg_vol_id
                result[f"{color.lower()}_volume_name"] = bg_vol_name
                result[f"linking_enabled_{color.lower()}"] = linked
                result[f"{color.lower()}_slice_offset"] = offset
                
        except Exception as e:
            print(f"Error accessing {color} view: {e}")
    
    # Get all loaded volumes
    volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    result["volumes_loaded"] = [node.GetName() for node in volume_nodes]
    
    # Check if different volumes are displayed in different views
    vol_ids = set()
    for color in ['Red', 'Yellow', 'Green']:
        view_info = result["slice_views"].get(color, {})
        vol_id = view_info.get("volume_id", "")
        if vol_id:
            vol_ids.add(vol_id)
    result["different_volumes_displayed"] = len(vol_ids) >= 2
    
    # Check if offsets are synchronized (within 1mm)
    offsets = []
    for color in ['Red', 'Yellow', 'Green']:
        view_info = result["slice_views"].get(color, {})
        if view_info.get("visible"):
            offsets.append(view_info.get("slice_offset", 0))
    
    if len(offsets) >= 2:
        max_diff = max(offsets) - min(offsets)
        result["offsets_synchronized"] = max_diff < 1.0
    
except Exception as e:
    result["error"] = str(e)
    print(f"Error querying Slicer state: {e}")

# Write result
output_path = "/tmp/slicer_state.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Slicer state saved to {output_path}")
print(json.dumps(result, indent=2))
PYEOF

chmod 644 "$SLICER_STATE_SCRIPT"

# Execute state query if Slicer is running
SLICER_STATE="{}"
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Querying Slicer state..."
    
    # Run Python script in Slicer
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script "$SLICER_STATE_SCRIPT" > /tmp/slicer_query.log 2>&1 &
    QUERY_PID=$!
    sleep 15
    
    # Read state if available
    if [ -f /tmp/slicer_state.json ]; then
        SLICER_STATE=$(cat /tmp/slicer_state.json)
        echo "Slicer state retrieved"
    else
        echo "Warning: Could not retrieve Slicer state"
        SLICER_STATE="{\"error\": \"State query timed out\"}"
    fi
    
    # Kill the query process
    kill $QUERY_PID 2>/dev/null || true
fi

# Check for user-saved screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k "$EXPECTED_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
    
    # Check if created during task
    SCREENSHOT_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    
    # Copy to temp for verification
    cp "$EXPECTED_SCREENSHOT" /tmp/user_screenshot.png 2>/dev/null || true
fi

# Also check for any new screenshots in exports directory
INITIAL_COUNT=$(cat /tmp/initial_screenshot_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(ls -1 "$EXPORTS_DIR"/*.png 2>/dev/null | wc -l || echo "0")
NEW_SCREENSHOTS=$((FINAL_COUNT - INITIAL_COUNT))

# Find newest screenshot if any
NEWEST_SCREENSHOT=""
if [ "$NEW_SCREENSHOTS" -gt 0 ]; then
    NEWEST_SCREENSHOT=$(ls -t "$EXPORTS_DIR"/*.png 2>/dev/null | head -1)
fi

# Extract key values from Slicer state JSON
LAYOUT_ID=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('layout_id', -1))" 2>/dev/null || echo "-1")
LAYOUT_NAME=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('layout_name', ''))" 2>/dev/null || echo "")
NUM_VIEWS=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('num_slice_views', 0))" 2>/dev/null || echo "0")
DIFF_VOLUMES=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('different_volumes_displayed', False) else 'false')" 2>/dev/null || echo "false")
OFFSETS_SYNC=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('offsets_synchronized', False) else 'false')" 2>/dev/null || echo "false")
RED_LINKED=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('linking_enabled_red', False) else 'false')" 2>/dev/null || echo "false")
YELLOW_LINKED=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('linking_enabled_yellow', False) else 'false')" 2>/dev/null || echo "false")
RED_VOL=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('red_volume_name', ''))" 2>/dev/null || echo "")
YELLOW_VOL=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('yellow_volume_name', ''))" 2>/dev/null || echo "")

# Determine if multi-view layout is active
MULTIVIEW_LAYOUTS="2 3 12 13 14 15 23 24 25 26 27 28 29 30"
IS_MULTIVIEW="false"
for lid in $MULTIVIEW_LAYOUTS; do
    if [ "$LAYOUT_ID" = "$lid" ]; then
        IS_MULTIVIEW="true"
        break
    fi
done

# Check if any linking is enabled
ANY_LINKING="false"
if [ "$RED_LINKED" = "true" ] || [ "$YELLOW_LINKED" = "true" ]; then
    ANY_LINKING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "layout_id": $LAYOUT_ID,
    "layout_name": "$LAYOUT_NAME",
    "is_multiview_layout": $IS_MULTIVIEW,
    "num_slice_views": $NUM_VIEWS,
    "different_volumes_displayed": $DIFF_VOLUMES,
    "red_volume_name": "$RED_VOL",
    "yellow_volume_name": "$YELLOW_VOL",
    "linking_enabled_red": $RED_LINKED,
    "linking_enabled_yellow": $YELLOW_LINKED,
    "any_linking_enabled": $ANY_LINKING,
    "offsets_synchronized": $OFFSETS_SYNC,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "new_screenshots_count": $NEW_SCREENSHOTS,
    "slicer_state": $SLICER_STATE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/linked_views_result.json 2>/dev/null || sudo rm -f /tmp/linked_views_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/linked_views_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/linked_views_result.json
chmod 666 /tmp/linked_views_result.json 2>/dev/null || sudo chmod 666 /tmp/linked_views_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/linked_views_result.json"
cat /tmp/linked_views_result.json
echo ""
echo "=== Export Complete ==="