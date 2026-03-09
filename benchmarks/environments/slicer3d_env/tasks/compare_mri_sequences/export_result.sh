#!/bin/bash
echo "=== Exporting Compare MRI Sequences Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get sample ID
SAMPLE_ID=$(cat /tmp/current_sample_id.txt 2>/dev/null || echo "BraTS2021_00000")
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
SCREENSHOTS_DIR="/home/ga/Documents/SlicerData/Screenshots"
EXPECTED_SCREENSHOT="$SCREENSHOTS_DIR/mri_comparison.png"

# Take final screenshot of Slicer state
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# ============================================================
# Check screenshot file
# ============================================================
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_BYTES=0
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_BYTES=$(stat -c%s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c%Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
        echo "Screenshot found: $EXPECTED_SCREENSHOT ($SCREENSHOT_SIZE_BYTES bytes)"
        echo "  Created during task: yes"
    else
        echo "Screenshot exists but was not created during task"
    fi
fi

# Also check for any new screenshots in the directory
NEW_SCREENSHOT_COUNT=0
INITIAL_COUNT=$(cat /tmp/initial_screenshot_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$SCREENSHOTS_DIR"/*.png 2>/dev/null | wc -l || echo "0")
NEW_SCREENSHOT_COUNT=$((CURRENT_COUNT - INITIAL_COUNT))

# Find latest screenshot
LATEST_SCREENSHOT=""
if [ -d "$SCREENSHOTS_DIR" ]; then
    LATEST_SCREENSHOT=$(ls -t "$SCREENSHOTS_DIR"/*.png 2>/dev/null | head -1 || echo "")
fi

# ============================================================
# Query Slicer state via Python API
# ============================================================
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running, querying state..."
    
    # Create Python script to query Slicer state
    cat > /tmp/query_slicer_state.py << 'PYEOF'
import json
import sys
import os

result = {
    "volume_count": 0,
    "volume_names": [],
    "volume_dimensions": [],
    "layout_id": -1,
    "layout_name": "unknown",
    "slice_view_count": 0,
    "visible_volumes_per_view": {},
    "error": None
}

try:
    import slicer
    
    # Get all scalar volume nodes
    nodes = slicer.mrmlScene.GetNodesByClass('vtkMRMLScalarVolumeNode')
    nodes.InitTraversal()
    
    volumes = []
    for i in range(nodes.GetNumberOfItems()):
        node = nodes.GetNextItemAsObject()
        if node:
            name = node.GetName()
            dims = [0, 0, 0]
            if node.GetImageData():
                dims = list(node.GetImageData().GetDimensions())
            volumes.append({
                "name": name,
                "dimensions": dims
            })
    
    result["volume_count"] = len(volumes)
    result["volume_names"] = [v["name"] for v in volumes]
    result["volume_dimensions"] = [v["dimensions"] for v in volumes]
    
    # Get layout info
    lm = slicer.app.layoutManager()
    if lm:
        result["layout_id"] = lm.layout
        result["slice_view_count"] = len(lm.sliceViewNames())
        
        # Map layout IDs to names
        layout_names = {
            1: "Conventional",
            2: "Four-Up", 
            3: "Dual 3D",
            4: "3x3",
            5: "One-Up Red Slice",
            6: "One-Up Yellow Slice",
            7: "One-Up Green Slice",
            12: "Compare",
            13: "Side by Side",
            19: "Four-Up Quantitative",
            21: "Three Over Three",
            23: "Tabbed 3D",
            24: "Tabbed Slice"
        }
        result["layout_name"] = layout_names.get(lm.layout, f"Layout_{lm.layout}")
        
        # Get visible volume in each slice view
        for view_name in lm.sliceViewNames():
            try:
                slice_widget = lm.sliceWidget(view_name)
                if slice_widget:
                    slice_logic = slice_widget.sliceLogic()
                    composite_node = slice_logic.GetSliceCompositeNode()
                    if composite_node:
                        bg_vol_id = composite_node.GetBackgroundVolumeID()
                        if bg_vol_id:
                            bg_node = slicer.mrmlScene.GetNodeByID(bg_vol_id)
                            if bg_node:
                                result["visible_volumes_per_view"][view_name] = bg_node.GetName()
            except Exception as e:
                result["visible_volumes_per_view"][view_name] = f"error: {e}"

except Exception as e:
    result["error"] = str(e)

# Output JSON
print(json.dumps(result))
PYEOF

    # Run the query script
    SLICER_STATE=$(sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window \
        --python-script /tmp/query_slicer_state.py 2>/dev/null | tail -1 || echo '{"error": "query failed"}')
    
    echo "Slicer state: $SLICER_STATE"
else
    SLICER_STATE='{"error": "Slicer not running", "volume_count": 0, "volume_names": [], "layout_id": -1}'
    echo "WARNING: 3D Slicer is not running!"
fi

# ============================================================
# Parse Slicer state
# ============================================================
VOLUME_COUNT=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('volume_count', 0))" 2>/dev/null || echo "0")
LAYOUT_ID=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('layout_id', -1))" 2>/dev/null || echo "-1")
LAYOUT_NAME=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('layout_name', 'unknown'))" 2>/dev/null || echo "unknown")
SLICE_VIEW_COUNT=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('slice_view_count', 0))" 2>/dev/null || echo "0")

# Check which sequences were loaded
T1_LOADED="false"
T1CE_LOADED="false"
T2_LOADED="false"
FLAIR_LOADED="false"

VOLUME_NAMES=$(echo "$SLICER_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(' '.join(d.get('volume_names', [])))" 2>/dev/null || echo "")

if echo "$VOLUME_NAMES" | grep -qi "_t1\|_t1\."; then
    T1_LOADED="true"
fi
if echo "$VOLUME_NAMES" | grep -qi "t1ce\|t1_ce"; then
    T1CE_LOADED="true"
fi
if echo "$VOLUME_NAMES" | grep -qi "_t2\|_t2\."; then
    T2_LOADED="true"
fi
if echo "$VOLUME_NAMES" | grep -qi "flair"; then
    FLAIR_LOADED="true"
fi

# Check if layout is multi-panel (not default single-slice views)
LAYOUT_IS_MULTIPANEL="false"
# Default conventional layout is 1, single-slice layouts are 5,6,7
# Multi-panel layouts: 2 (Four-Up), 3 (Dual 3D), 4 (3x3), 12 (Compare), 13 (Side by Side), etc.
if [ "$LAYOUT_ID" -eq 2 ] || [ "$LAYOUT_ID" -eq 3 ] || [ "$LAYOUT_ID" -eq 4 ] || \
   [ "$LAYOUT_ID" -eq 12 ] || [ "$LAYOUT_ID" -eq 13 ] || [ "$LAYOUT_ID" -eq 19 ] || \
   [ "$LAYOUT_ID" -eq 21 ] || [ "$SLICE_VIEW_COUNT" -ge 4 ]; then
    LAYOUT_IS_MULTIPANEL="true"
fi

echo ""
echo "=== State Summary ==="
echo "Volumes loaded: $VOLUME_COUNT"
echo "Volume names: $VOLUME_NAMES"
echo "T1 loaded: $T1_LOADED"
echo "T1ce loaded: $T1CE_LOADED"
echo "T2 loaded: $T2_LOADED"
echo "FLAIR loaded: $FLAIR_LOADED"
echo "Layout ID: $LAYOUT_ID ($LAYOUT_NAME)"
echo "Layout is multi-panel: $LAYOUT_IS_MULTIPANEL"
echo "Slice view count: $SLICE_VIEW_COUNT"
echo "Screenshot exists: $SCREENSHOT_EXISTS"
echo "Screenshot size: $SCREENSHOT_SIZE_BYTES bytes"

# ============================================================
# Build result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sample_id": "$SAMPLE_ID",
    "slicer_running": $SLICER_RUNNING,
    "volume_count": $VOLUME_COUNT,
    "volume_names": "$VOLUME_NAMES",
    "t1_loaded": $T1_LOADED,
    "t1ce_loaded": $T1CE_LOADED,
    "t2_loaded": $T2_LOADED,
    "flair_loaded": $FLAIR_LOADED,
    "layout_id": $LAYOUT_ID,
    "layout_name": "$LAYOUT_NAME",
    "layout_is_multipanel": $LAYOUT_IS_MULTIPANEL,
    "slice_view_count": $SLICE_VIEW_COUNT,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE_BYTES,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "new_screenshot_count": $NEW_SCREENSHOT_COUNT,
    "latest_screenshot": "$LATEST_SCREENSHOT",
    "slicer_state": $SLICER_STATE
}
EOF

# Move to final location with permission handling
rm -f /tmp/mri_compare_result.json 2>/dev/null || sudo rm -f /tmp/mri_compare_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/mri_compare_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/mri_compare_result.json
chmod 666 /tmp/mri_compare_result.json 2>/dev/null || sudo chmod 666 /tmp/mri_compare_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/mri_compare_result.json"
cat /tmp/mri_compare_result.json
echo ""
echo "=== Export Complete ==="