#!/bin/bash
echo "=== Exporting Optimal Slice Selection Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_SCREENSHOT="$BRATS_DIR/optimal_slices_view.png"
OUTPUT_MEASUREMENTS="$BRATS_DIR/tumor_dimensions.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/slice_report.json"

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/optimal_slice_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export current slice positions and measurements from Slicer
    cat > /tmp/export_slice_data.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Get current slice positions
slice_positions = {}
for color, plane in [("Red", "axial"), ("Green", "coronal"), ("Yellow", "sagittal")]:
    sliceWidget = slicer.app.layoutManager().sliceWidget(color)
    if sliceWidget:
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        offset = sliceNode.GetSliceOffset()
        slice_positions[plane] = {
            "offset_mm": offset,
            "view_color": color
        }
        print(f"{plane} ({color}): offset = {offset:.2f} mm")

# Try to convert offsets to slice indices using volume info
volume_node = slicer.util.getNode("FLAIR")
if volume_node:
    # Get volume geometry
    imageData = volume_node.GetImageData()
    dims = imageData.GetDimensions()
    spacing = volume_node.GetSpacing()
    origin = volume_node.GetOrigin()
    
    print(f"\nVolume info: dims={dims}, spacing={spacing}, origin={origin}")
    
    # Estimate slice indices from offsets
    for plane, data in slice_positions.items():
        offset = data["offset_mm"]
        if plane == "axial":
            # Axial slices vary along Z (index 2)
            slice_idx = int(round((offset - origin[2]) / spacing[2]))
            slice_idx = max(0, min(dims[2]-1, slice_idx))
        elif plane == "sagittal":
            # Sagittal slices vary along X (index 0)
            slice_idx = int(round((offset - origin[0]) / spacing[0]))
            slice_idx = max(0, min(dims[0]-1, slice_idx))
        elif plane == "coronal":
            # Coronal slices vary along Y (index 1)
            slice_idx = int(round((offset - origin[1]) / spacing[1]))
            slice_idx = max(0, min(dims[1]-1, slice_idx))
        else:
            slice_idx = 0
        slice_positions[plane]["estimated_slice_index"] = slice_idx
        print(f"{plane}: estimated slice index = {slice_idx}")

# Export measurements from markup nodes
measurements = []
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"\nFound {len(line_nodes)} line markup(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
        measurements.append({
            "name": node.GetName(),
            "type": "line",
            "length_mm": round(length, 2),
            "p1": [round(x, 2) for x in p1],
            "p2": [round(x, 2) for x in p2]
        })
        print(f"  {node.GetName()}: {length:.2f} mm")

# Save slice positions
positions_path = os.path.join(output_dir, "slicer_slice_positions.json")
with open(positions_path, "w") as f:
    json.dump(slice_positions, f, indent=2)
print(f"\nSlice positions saved to {positions_path}")

# Save measurements
if measurements:
    meas_path = os.path.join(output_dir, "tumor_dimensions.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Measurements saved to {meas_path}")
    
    # Also save individual markup nodes
    for node in line_nodes:
        node_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        slicer.util.saveNode(node, node_path)

print("\nExport complete")
PYEOF

    # Run export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_slice_data.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_slice_data" 2>/dev/null || true
fi

# Check for agent's screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE=0
SCREENSHOT_CREATED_DURING_TASK="false"

POSSIBLE_SCREENSHOT_PATHS=(
    "$OUTPUT_SCREENSHOT"
    "$BRATS_DIR/screenshot.png"
    "$BRATS_DIR/view.png"
    "/home/ga/Documents/optimal_slices_view.png"
)

for path in "${POSSIBLE_SCREENSHOT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SCREENSHOT_EXISTS="true"
        SCREENSHOT_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SCREENSHOT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
            SCREENSHOT_CREATED_DURING_TASK="true"
        fi
        if [ "$path" != "$OUTPUT_SCREENSHOT" ]; then
            cp "$path" "$OUTPUT_SCREENSHOT" 2>/dev/null || true
        fi
        echo "Found screenshot: $path (${SCREENSHOT_SIZE} bytes)"
        break
    fi
done

# Check for agent's measurement file
MEASUREMENTS_EXISTS="false"
MEASUREMENTS_PATH=""
MEASUREMENT_COUNT=0

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENTS"
    "$BRATS_DIR/measurements.mrk.json"
    "$BRATS_DIR/ruler.mrk.json"
    "/home/ga/Documents/tumor_dimensions.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENTS_EXISTS="true"
        MEASUREMENTS_PATH="$path"
        MEASUREMENT_COUNT=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    meas = data.get('measurements', [])
    print(len(meas))
except:
    print(0)
" 2>/dev/null || echo "0")
        if [ "$path" != "$OUTPUT_MEASUREMENTS" ]; then
            cp "$path" "$OUTPUT_MEASUREMENTS" 2>/dev/null || true
        fi
        echo "Found measurements: $path ($MEASUREMENT_COUNT measurements)"
        break
    fi
done

# Check for agent's report
REPORT_EXISTS="false"
REPORT_PATH=""
AGENT_AXIAL_SLICE=""
AGENT_SAGITTAL_SLICE=""
AGENT_CORONAL_SLICE=""
AGENT_AXIAL_DIAM=""
AGENT_SAGITTAL_DIAM=""
AGENT_CORONAL_DIAM=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/slices.json"
    "/home/ga/Documents/slice_report.json"
    "/home/ga/slice_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract values from report
        AGENT_AXIAL_SLICE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('axial_slice_index', ''))" 2>/dev/null || echo "")
        AGENT_SAGITTAL_SLICE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('sagittal_slice_index', ''))" 2>/dev/null || echo "")
        AGENT_CORONAL_SLICE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('coronal_slice_index', ''))" 2>/dev/null || echo "")
        AGENT_AXIAL_DIAM=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('axial_diameter_mm', ''))" 2>/dev/null || echo "")
        AGENT_SAGITTAL_DIAM=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('sagittal_diameter_mm', ''))" 2>/dev/null || echo "")
        AGENT_CORONAL_DIAM=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('coronal_diameter_mm', ''))" 2>/dev/null || echo "")
        
        echo "Found report: $path"
        echo "  Axial: slice=$AGENT_AXIAL_SLICE, diameter=$AGENT_AXIAL_DIAM"
        echo "  Sagittal: slice=$AGENT_SAGITTAL_SLICE, diameter=$AGENT_SAGITTAL_DIAM"
        echo "  Coronal: slice=$AGENT_CORONAL_SLICE, diameter=$AGENT_CORONAL_DIAM"
        break
    fi
done

# If no explicit report, try to extract from Slicer's exported slice positions
if [ "$REPORT_EXISTS" = "false" ] && [ -f "$BRATS_DIR/slicer_slice_positions.json" ]; then
    echo "No agent report found, using Slicer slice positions..."
    AGENT_AXIAL_SLICE=$(python3 -c "import json; d=json.load(open('$BRATS_DIR/slicer_slice_positions.json')); print(d.get('axial', {}).get('estimated_slice_index', ''))" 2>/dev/null || echo "")
    AGENT_SAGITTAL_SLICE=$(python3 -c "import json; d=json.load(open('$BRATS_DIR/slicer_slice_positions.json')); print(d.get('sagittal', {}).get('estimated_slice_index', ''))" 2>/dev/null || echo "")
    AGENT_CORONAL_SLICE=$(python3 -c "import json; d=json.load(open('$BRATS_DIR/slicer_slice_positions.json')); print(d.get('coronal', {}).get('estimated_slice_index', ''))" 2>/dev/null || echo "")
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_optimal_slices.json" /tmp/ground_truth_optimal_slices.json 2>/dev/null || true
chmod 644 /tmp/ground_truth_optimal_slices.json 2>/dev/null || true

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "measurements_exists": $MEASUREMENTS_EXISTS,
    "measurement_count": $MEASUREMENT_COUNT,
    "report_exists": $REPORT_EXISTS,
    "agent_values": {
        "axial_slice_index": "$AGENT_AXIAL_SLICE",
        "axial_diameter_mm": "$AGENT_AXIAL_DIAM",
        "sagittal_slice_index": "$AGENT_SAGITTAL_SLICE",
        "sagittal_diameter_mm": "$AGENT_SAGITTAL_DIAM",
        "coronal_slice_index": "$AGENT_CORONAL_SLICE",
        "coronal_diameter_mm": "$AGENT_CORONAL_DIAM"
    },
    "sample_id": "$SAMPLE_ID",
    "final_screenshot_path": "/tmp/optimal_slice_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/optimal_slice_result.json 2>/dev/null || sudo rm -f /tmp/optimal_slice_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/optimal_slice_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/optimal_slice_result.json
chmod 666 /tmp/optimal_slice_result.json 2>/dev/null || sudo chmod 666 /tmp/optimal_slice_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/optimal_slice_result.json
echo ""
echo "=== Export Complete ==="