#!/bin/bash
echo "=== Exporting HU Tissue Characterization Result ==="

source /workspace/scripts/task_utils.sh

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get the case ID used
if [ -f /tmp/hu_task_case_id.txt ]; then
    CASE_ID=$(cat /tmp/hu_task_case_id.txt)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_ROIS="$AMOS_DIR/tissue_rois.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/hu_tissue_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/hu_task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any markups from Slicer before closing
    cat > /tmp/export_hu_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

all_markups = []

# Check for fiducial markups (points/ROIs)
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        all_markups.append({
            "node_name": node.GetName(),
            "label": label,
            "type": "fiducial",
            "position_ras": pos,
        })
        print(f"  Point '{label}': RAS={pos}")

# Check for ROI nodes
roi_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsROINode")
print(f"Found {len(roi_nodes)} ROI node(s)")

for node in roi_nodes:
    center = [0.0, 0.0, 0.0]
    node.GetCenter(center)
    size = [0.0, 0.0, 0.0]
    node.GetSize(size)
    all_markups.append({
        "node_name": node.GetName(),
        "label": node.GetName(),
        "type": "roi",
        "center_ras": center,
        "size_mm": size,
    })
    print(f"  ROI '{node.GetName()}': center={center}, size={size}")

# Check for line markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line node(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        all_markups.append({
            "node_name": node.GetName(),
            "type": "line",
            "p1": p1,
            "p2": p2,
        })

# Save all markups
if all_markups:
    markups_path = os.path.join(output_dir, "tissue_rois.mrk.json")
    with open(markups_path, "w") as f:
        json.dump({"markups": all_markups, "count": len(all_markups)}, f, indent=2)
    print(f"Exported {len(all_markups)} markups to {markups_path}")
    
    # Also save each markup node to individual files
    for node in fid_nodes + roi_nodes:
        try:
            node_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
            slicer.util.saveNode(node, node_path)
        except Exception as e:
            print(f"Could not save node {node.GetName()}: {e}")
else:
    print("No markups found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_hu_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_hu_markups" 2>/dev/null || true
fi

# Check if agent saved ROI file
ROIS_EXISTS="false"
ROIS_PATH=""
ROIS_COUNT=0
ROIS_CREATED_DURING_TASK="false"

POSSIBLE_ROI_PATHS=(
    "$OUTPUT_ROIS"
    "$AMOS_DIR/tissue_rois.mrk.json"
    "$AMOS_DIR/rois.mrk.json"
    "$AMOS_DIR/markups.mrk.json"
    "/home/ga/Documents/tissue_rois.mrk.json"
)

for path in "${POSSIBLE_ROI_PATHS[@]}"; do
    if [ -f "$path" ]; then
        ROIS_EXISTS="true"
        ROIS_PATH="$path"
        echo "Found ROIs at: $path"
        
        # Check if created during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            ROIS_CREATED_DURING_TASK="true"
        fi
        
        # Copy to expected location if needed
        if [ "$path" != "$OUTPUT_ROIS" ]; then
            cp "$path" "$OUTPUT_ROIS" 2>/dev/null || true
        fi
        
        # Count markups
        ROIS_COUNT=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    markups = data.get('markups', [])
    print(len(markups))
except:
    print(0)
" 2>/dev/null || echo "0")
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_CREATED_DURING_TASK="false"
MEASUREMENTS_COUNT=0

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/hu_tissue_report.json"
    "$AMOS_DIR/hu_report.json"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/measurements.json"
    "/home/ga/Documents/hu_tissue_report.json"
    "/home/ga/hu_tissue_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Check if created during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        
        # Copy to expected location if needed
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Count measurements
        MEASUREMENTS_COUNT=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    measurements = data.get('measurements', [])
    print(len(measurements))
except:
    print(0)
" 2>/dev/null || echo "0")
        break
    fi
done

# Copy report to /tmp for verifier access
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_hu_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_hu_report.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_ROIS" ]; then
    cp "$OUTPUT_ROIS" /tmp/agent_tissue_rois.json 2>/dev/null || true
    chmod 644 /tmp/agent_tissue_rois.json 2>/dev/null || true
fi

# Copy ground truth for verification
if [ -f "$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json" ]; then
    cp "$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json" /tmp/hu_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/hu_ground_truth.json 2>/dev/null || true
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "rois_exists": $ROIS_EXISTS,
    "rois_path": "$ROIS_PATH",
    "rois_count": $ROIS_COUNT,
    "rois_created_during_task": $ROIS_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "measurements_count": $MEASUREMENTS_COUNT,
    "case_id": "$CASE_ID",
    "screenshot_exists": $([ -f "/tmp/hu_task_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/hu_task_result.json 2>/dev/null || sudo rm -f /tmp/hu_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/hu_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/hu_task_result.json
chmod 666 /tmp/hu_task_result.json 2>/dev/null || sudo chmod 666 /tmp/hu_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/hu_task_result.json
echo ""

# Show agent report if exists
if [ -f "/tmp/agent_hu_report.json" ]; then
    echo ""
    echo "Agent HU Report:"
    cat /tmp/agent_hu_report.json
    echo ""
fi

echo "=== Export Complete ==="