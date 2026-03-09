#!/bin/bash
echo "=== Exporting Locate Maximum Tumor Slice Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# Get sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Extract fiducial positions from Slicer
FIDUCIALS_EXTRACTED="false"
FIDUCIAL_COUNT=0
FIDUCIAL_DATA="[]"

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting fiducial positions from Slicer..."
    
    cat > /tmp/extract_fiducials.py << 'PYEOF'
import slicer
import json
import os

output_path = "/tmp/fiducial_positions.json"

fiducials = []
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")

print(f"Found {len(fiducial_nodes)} fiducial node(s)")

for node in fiducial_nodes:
    node_name = node.GetName()
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node_name}': {n_points} point(s)")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        
        fiducial = {
            "node_name": node_name,
            "point_index": i,
            "label": label,
            "position_ras": pos,
            "x": pos[0],
            "y": pos[1],
            "z": pos[2]
        }
        fiducials.append(fiducial)
        print(f"    Point {i} '{label}': RAS = ({pos[0]:.2f}, {pos[1]:.2f}, {pos[2]:.2f})")

result = {
    "fiducial_count": len(fiducials),
    "fiducials": fiducials
}

with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"\nExported {len(fiducials)} fiducial(s) to {output_path}")
PYEOF

    # Run extraction script
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/extract_fiducials.py --no-main-window" > /tmp/extract_fiducials.log 2>&1 &
    EXTRACT_PID=$!
    
    # Wait with timeout
    for i in $(seq 1 15); do
        if [ -f /tmp/fiducial_positions.json ]; then
            FIDUCIALS_EXTRACTED="true"
            break
        fi
        sleep 1
    done
    
    # Kill extraction process if still running
    kill $EXTRACT_PID 2>/dev/null || true
    
    if [ -f /tmp/fiducial_positions.json ]; then
        FIDUCIAL_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/fiducial_positions.json')).get('fiducial_count', 0))" 2>/dev/null || echo "0")
        FIDUCIAL_DATA=$(cat /tmp/fiducial_positions.json)
        echo "Extracted $FIDUCIAL_COUNT fiducial(s)"
    fi
fi

# Get current slice position from Slicer (if possible)
CURRENT_SLICE_Z="null"
if [ "$SLICER_RUNNING" = "true" ]; then
    cat > /tmp/get_slice_pos.py << 'SLICEPOS'
import slicer
import json

try:
    layoutManager = slicer.app.layoutManager()
    redWidget = layoutManager.sliceWidget("Red")
    if redWidget:
        sliceLogic = redWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        # Get the slice offset (position along the normal)
        offset = sliceNode.GetSliceOffset()
        print(json.dumps({"slice_offset": offset}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
SLICEPOS

    SLICE_INFO=$(su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-code '$(cat /tmp/get_slice_pos.py)' --no-main-window" 2>/dev/null | grep -o '{.*}' | head -1 || echo "{}")
    CURRENT_SLICE_Z=$(echo "$SLICE_INFO" | python3 -c "import json, sys; print(json.load(sys.stdin).get('slice_offset', 'null'))" 2>/dev/null || echo "null")
fi

# Load ground truth for comparison
GT_MAX_SLICE_Z="null"
GT_MAX_SLICE_IDX="null"
GT_CENTROID="null"
VOLUME_SHAPE="null"

if [ -f /tmp/max_slice_ground_truth.json ]; then
    GT_MAX_SLICE_Z=$(python3 -c "import json; print(json.load(open('/tmp/max_slice_ground_truth.json')).get('max_slice_z_ras', 'null'))" 2>/dev/null || echo "null")
    GT_MAX_SLICE_IDX=$(python3 -c "import json; print(json.load(open('/tmp/max_slice_ground_truth.json')).get('max_slice_index', 'null'))" 2>/dev/null || echo "null")
    GT_CENTROID=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/max_slice_ground_truth.json')).get('centroid_ras', [])))" 2>/dev/null || echo "null")
    VOLUME_SHAPE=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/max_slice_ground_truth.json')).get('volume_shape', [])))" 2>/dev/null || echo "null")
fi

# Check if files were modified during task
WORK_DONE="false"
if [ "$FIDUCIAL_COUNT" -gt 0 ]; then
    WORK_DONE="true"
fi

# Calculate slice offset if fiducial was placed
AGENT_FIDUCIAL_Z="null"
SLICE_OFFSET="null"
if [ "$FIDUCIAL_COUNT" -gt 0 ] && [ -f /tmp/fiducial_positions.json ]; then
    AGENT_FIDUCIAL_Z=$(python3 -c "
import json
data = json.load(open('/tmp/fiducial_positions.json'))
if data['fiducials']:
    # Take the first fiducial's Z coordinate
    print(data['fiducials'][0]['z'])
else:
    print('null')
" 2>/dev/null || echo "null")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "fiducials_extracted": $FIDUCIALS_EXTRACTED,
    "fiducial_count": $FIDUCIAL_COUNT,
    "agent_fiducial_z_ras": $AGENT_FIDUCIAL_Z,
    "current_slice_z": $CURRENT_SLICE_Z,
    "gt_max_slice_z_ras": $GT_MAX_SLICE_Z,
    "gt_max_slice_index": $GT_MAX_SLICE_IDX,
    "gt_centroid_ras": $GT_CENTROID,
    "volume_shape": $VOLUME_SHAPE,
    "work_done": $WORK_DONE,
    "sample_id": "$SAMPLE_ID",
    "screenshot_path": "/tmp/task_final.png",
    "fiducial_data_path": "/tmp/fiducial_positions.json"
}
EOF

# Move to final location
rm -f /tmp/max_slice_task_result.json 2>/dev/null || sudo rm -f /tmp/max_slice_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/max_slice_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/max_slice_task_result.json
chmod 666 /tmp/max_slice_task_result.json 2>/dev/null || sudo chmod 666 /tmp/max_slice_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/max_slice_task_result.json"
cat /tmp/max_slice_task_result.json

# Close Slicer
echo ""
echo "Closing 3D Slicer..."
close_slicer

echo "=== Export Complete ==="