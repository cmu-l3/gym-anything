#!/bin/bash
echo "=== Exporting Multi-Sequence Display Setup Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_SCREENSHOT="$BRATS_DIR/multisequence_comparison.png"
OUTPUT_FIDUCIAL="$BRATS_DIR/tumor_center.fcsv"
OUTPUT_REPORT="$BRATS_DIR/sequence_comparison_report.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/multisequence_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# ============================================================
# Extract current Slicer state before closing
# ============================================================
echo "Extracting Slicer state..."
cat > /tmp/extract_slicer_state.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/BraTS"
state_file = "/tmp/slicer_view_state.json"

state = {
    "layout_name": "",
    "slice_views": {},
    "fiducials": [],
    "volumes_in_scene": [],
    "views_linked": False,
}

try:
    # Get current layout
    layoutManager = slicer.app.layoutManager()
    layoutNode = slicer.app.layoutManager().layoutLogic().GetLayoutNode()
    layout_id = layoutNode.GetViewArrangement()
    
    # Map layout IDs to names
    layout_names = {
        0: "Conventional",
        2: "FourUp",
        3: "OneUp3D",
        4: "ThreeOverThree",
        6: "TabbedSlice",
        7: "Dual3D",
        15: "SideBySide",
        19: "FourOverFour",
    }
    state["layout_name"] = layout_names.get(layout_id, f"Layout_{layout_id}")
    state["layout_id"] = layout_id
    
    # Check if it's a four-panel layout
    state["is_four_panel"] = layout_id in [2, 19, 4]  # FourUp, FourOverFour, ThreeOverThree
    
    # Get info about each slice view
    slice_colors = ["Red", "Green", "Yellow"]
    
    # For FourUp layout, there's also a "Slice4" or we check all available
    if hasattr(layoutManager, 'sliceViewNames'):
        slice_colors = list(layoutManager.sliceViewNames())
    
    for color in slice_colors:
        try:
            sliceWidget = layoutManager.sliceWidget(color)
            if sliceWidget:
                sliceLogic = sliceWidget.sliceLogic()
                compositeNode = sliceLogic.GetSliceCompositeNode()
                sliceNode = sliceLogic.GetSliceNode()
                
                bg_id = compositeNode.GetBackgroundVolumeID()
                bg_node = slicer.mrmlScene.GetNodeByID(bg_id) if bg_id else None
                bg_name = bg_node.GetName() if bg_node else "None"
                
                # Get display settings
                displayNode = bg_node.GetDisplayNode() if bg_node else None
                window = displayNode.GetWindow() if displayNode else 0
                level = displayNode.GetLevel() if displayNode else 0
                
                # Check if linked
                linked = compositeNode.GetLinkedControl() if hasattr(compositeNode, 'GetLinkedControl') else False
                
                state["slice_views"][color] = {
                    "background_volume": bg_name,
                    "slice_offset": sliceNode.GetSliceOffset(),
                    "window": window,
                    "level": level,
                    "linked": bool(linked),
                }
                
                if linked:
                    state["views_linked"] = True
        except Exception as e:
            print(f"Error getting {color} view info: {e}")
    
    # Get list of volumes in scene
    volumeNodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    state["volumes_in_scene"] = [node.GetName() for node in volumeNodes]
    
    # Get fiducial information
    fiducialNodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
    for node in fiducialNodes:
        n_points = node.GetNumberOfControlPoints()
        for i in range(n_points):
            pos = [0.0, 0.0, 0.0]
            node.GetNthControlPointPosition(i, pos)
            label = node.GetNthControlPointLabel(i)
            state["fiducials"].append({
                "node_name": node.GetName(),
                "label": label,
                "position_ras": pos,
            })
    
    # Save any fiducial nodes to FCSV
    for node in fiducialNodes:
        fcsv_path = os.path.join(output_dir, "tumor_center.fcsv")
        slicer.util.saveNode(node, fcsv_path)
        print(f"Saved fiducial to {fcsv_path}")
    
    # Save state
    with open(state_file, "w") as f:
        json.dump(state, f, indent=2)
    print(f"Slicer state saved to {state_file}")
    
except Exception as e:
    print(f"Error extracting state: {e}")
    import traceback
    traceback.print_exc()
    
    # Save partial state
    with open(state_file, "w") as f:
        json.dump({"error": str(e)}, f)

print("State extraction complete")
PYEOF

# Run state extraction if Slicer is running
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Running state extraction in Slicer..."
    # Try to run Python in existing Slicer instance via socket if available
    # Otherwise start a headless instance
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/extract_slicer_state.py --no-main-window > /tmp/slicer_extract.log 2>&1 &
    EXTRACT_PID=$!
    sleep 15
    kill $EXTRACT_PID 2>/dev/null || true
fi

# ============================================================
# Check output files
# ============================================================

# Check screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE=0
SCREENSHOT_CREATED_DURING_TASK="false"

# Search for screenshot in multiple locations
POSSIBLE_SCREENSHOT_PATHS=(
    "$OUTPUT_SCREENSHOT"
    "$BRATS_DIR/multisequence_comparison.png"
    "$BRATS_DIR/screenshot.png"
    "$BRATS_DIR/comparison.png"
    "/home/ga/Documents/multisequence_comparison.png"
    "/home/ga/multisequence_comparison.png"
)

for path in "${POSSIBLE_SCREENSHOT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SCREENSHOT_EXISTS="true"
        SCREENSHOT_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SCREENSHOT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
            SCREENSHOT_CREATED_DURING_TASK="true"
        fi
        
        echo "Found screenshot at: $path (${SCREENSHOT_SIZE} bytes)"
        
        if [ "$path" != "$OUTPUT_SCREENSHOT" ]; then
            cp "$path" "$OUTPUT_SCREENSHOT" 2>/dev/null || true
        fi
        break
    fi
done

# Check fiducial file
FIDUCIAL_EXISTS="false"
FIDUCIAL_CREATED_DURING_TASK="false"
FIDUCIAL_POSITION=""

POSSIBLE_FIDUCIAL_PATHS=(
    "$OUTPUT_FIDUCIAL"
    "$BRATS_DIR/tumor_center.fcsv"
    "$BRATS_DIR/fiducial.fcsv"
    "$BRATS_DIR/F.fcsv"
    "/home/ga/Documents/tumor_center.fcsv"
)

for path in "${POSSIBLE_FIDUCIAL_PATHS[@]}"; do
    if [ -f "$path" ]; then
        FIDUCIAL_EXISTS="true"
        FIDUCIAL_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$FIDUCIAL_MTIME" -gt "$TASK_START" ]; then
            FIDUCIAL_CREATED_DURING_TASK="true"
        fi
        
        echo "Found fiducial at: $path"
        
        # Extract position from FCSV file (CSV format)
        FIDUCIAL_POSITION=$(grep -v "^#" "$path" | head -1 | cut -d',' -f2,3,4 2>/dev/null || echo "")
        
        if [ "$path" != "$OUTPUT_FIDUCIAL" ]; then
            cp "$path" "$OUTPUT_FIDUCIAL" 2>/dev/null || true
        fi
        break
    fi
done

# Check report file
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_VALID_JSON="false"
REPORT_HAS_REQUIRED_FIELDS="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/sequence_comparison_report.json"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/sequence_comparison_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        
        echo "Found report at: $path"
        
        # Validate JSON and check fields
        REPORT_FIELDS=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    fields = []
    if 'case_id' in data: fields.append('case_id')
    if 'slice_position_mm' in data or 'slice_position' in data: fields.append('slice_position')
    if 'tumor_center_ras' in data or 'tumor_center' in data: fields.append('tumor_center')
    if 'sequence_assessment' in data: fields.append('sequence_assessment')
    if 'estimated_tumor_size_mm' in data or 'tumor_size' in data: fields.append('tumor_size')
    print(','.join(fields))
    print('VALID_JSON')
except Exception as e:
    print(f'ERROR:{e}')
" 2>/dev/null || echo "ERROR")
        
        if echo "$REPORT_FIELDS" | grep -q "VALID_JSON"; then
            REPORT_VALID_JSON="true"
            FIELD_COUNT=$(echo "$REPORT_FIELDS" | head -1 | tr ',' '\n' | wc -l)
            if [ "$FIELD_COUNT" -ge 3 ]; then
                REPORT_HAS_REQUIRED_FIELDS="true"
            fi
        fi
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# ============================================================
# Read Slicer view state
# ============================================================
LAYOUT_NAME=""
IS_FOUR_PANEL="false"
VIEWS_LINKED="false"
VOLUMES_DISPLAYED=""

if [ -f /tmp/slicer_view_state.json ]; then
    LAYOUT_NAME=$(python3 -c "import json; print(json.load(open('/tmp/slicer_view_state.json')).get('layout_name', ''))" 2>/dev/null || echo "")
    IS_FOUR_PANEL=$(python3 -c "import json; print('true' if json.load(open('/tmp/slicer_view_state.json')).get('is_four_panel', False) else 'false')" 2>/dev/null || echo "false")
    VIEWS_LINKED=$(python3 -c "import json; print('true' if json.load(open('/tmp/slicer_view_state.json')).get('views_linked', False) else 'false')" 2>/dev/null || echo "false")
    
    # Get volumes displayed in each view
    VOLUMES_DISPLAYED=$(python3 -c "
import json
data = json.load(open('/tmp/slicer_view_state.json'))
views = data.get('slice_views', {})
vols = [v.get('background_volume', 'None') for v in views.values()]
print(','.join(vols))
" 2>/dev/null || echo "")
fi

# Copy ground truth centroid for verification
cp /tmp/tumor_centroid_gt.json /tmp/gt_centroid.json 2>/dev/null || true
chmod 644 /tmp/gt_centroid.json 2>/dev/null || true

# Copy outputs for verifier
cp "$OUTPUT_SCREENSHOT" /tmp/agent_screenshot.png 2>/dev/null || true
cp "$OUTPUT_FIDUCIAL" /tmp/agent_fiducial.fcsv 2>/dev/null || true
cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
cp /tmp/slicer_view_state.json /tmp/view_state.json 2>/dev/null || true
chmod 644 /tmp/agent_screenshot.png /tmp/agent_fiducial.fcsv /tmp/agent_report.json /tmp/view_state.json 2>/dev/null || true

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "sample_id": "$SAMPLE_ID",
    "layout": {
        "name": "$LAYOUT_NAME",
        "is_four_panel": $IS_FOUR_PANEL,
        "views_linked": $VIEWS_LINKED,
        "volumes_displayed": "$VOLUMES_DISPLAYED"
    },
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "size_bytes": $SCREENSHOT_SIZE,
        "created_during_task": $SCREENSHOT_CREATED_DURING_TASK
    },
    "fiducial": {
        "exists": $FIDUCIAL_EXISTS,
        "created_during_task": $FIDUCIAL_CREATED_DURING_TASK,
        "position": "$FIDUCIAL_POSITION"
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "valid_json": $REPORT_VALID_JSON,
        "has_required_fields": $REPORT_HAS_REQUIRED_FIELDS
    },
    "final_screenshot_path": "/tmp/multisequence_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/multisequence_task_result.json 2>/dev/null || sudo rm -f /tmp/multisequence_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/multisequence_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/multisequence_task_result.json
chmod 666 /tmp/multisequence_task_result.json 2>/dev/null || sudo chmod 666 /tmp/multisequence_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/multisequence_task_result.json
echo ""
echo "=== Export Complete ==="