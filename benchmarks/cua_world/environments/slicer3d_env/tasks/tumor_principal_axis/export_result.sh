#!/bin/bash
echo "=== Exporting Tumor Principal Axis Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Get sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_CENTROID="$BRATS_DIR/tumor_centroid.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/principal_axis_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/principal_axis_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any markups from Slicer
    cat > /tmp/export_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Export fiducial markups (for centroid)
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fiducial_nodes)} fiducial node(s)")

centroid_data = None
for node in fiducial_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points > 0:
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, pos)
        centroid_data = {
            "name": node.GetName(),
            "centroid_ras": pos,
            "n_points": n_points
        }
        print(f"Fiducial '{node.GetName()}': position {pos}")
        
        # Save markup node directly
        mrk_path = os.path.join(output_dir, "tumor_centroid.mrk.json")
        slicer.util.saveNode(node, mrk_path)
        print(f"Saved fiducial to {mrk_path}")
        break

# Export line markups (for measurements)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line node(s)")

measurements = []
for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        measurements.append({
            "name": node.GetName(),
            "length_mm": length,
            "p1": p1,
            "p2": p2
        })
        print(f"Line '{node.GetName()}': {length:.2f} mm")

# Save measurements summary
if measurements or centroid_data:
    summary = {
        "centroid": centroid_data,
        "measurements": measurements
    }
    summary_path = os.path.join(output_dir, "slicer_markups_summary.json")
    with open(summary_path, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"Saved summary to {summary_path}")

print("Export complete")
PYEOF

    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_markups" 2>/dev/null || true
fi

# Check for centroid markup file
CENTROID_EXISTS="false"
CENTROID_PATH=""
CENTROID_RAS=""

POSSIBLE_CENTROID_PATHS=(
    "$OUTPUT_CENTROID"
    "$BRATS_DIR/tumor_centroid.mrk.json"
    "$BRATS_DIR/centroid.mrk.json"
    "/home/ga/Documents/tumor_centroid.mrk.json"
)

for path in "${POSSIBLE_CENTROID_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CENTROID_EXISTS="true"
        CENTROID_PATH="$path"
        CENTROID_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found centroid file at: $path"
        
        # Try to extract centroid position
        CENTROID_RAS=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
# Handle Slicer markup format
if 'markups' in data:
    for markup in data['markups']:
        if 'controlPoints' in markup:
            for cp in markup['controlPoints']:
                pos = cp.get('position', [0,0,0])
                print(f'{pos[0]},{pos[1]},{pos[2]}')
                break
            break
elif 'centroid_ras' in data:
    pos = data['centroid_ras']
    print(f'{pos[0]},{pos[1]},{pos[2]}')
" 2>/dev/null || echo "")
        
        if [ "$path" != "$OUTPUT_CENTROID" ]; then
            cp "$path" "$OUTPUT_CENTROID" 2>/dev/null || true
        fi
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_DATA=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/principal_axis_report.json"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/geometry_report.json"
    "/home/ga/Documents/principal_axis_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found report file at: $path"
        
        REPORT_DATA=$(cat "$path" 2>/dev/null || echo "{}")
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Check if files were created during task (anti-gaming)
CENTROID_CREATED_DURING_TASK="false"
if [ "$CENTROID_EXISTS" = "true" ] && [ "${CENTROID_MTIME:-0}" -gt "$TASK_START" ]; then
    CENTROID_CREATED_DURING_TASK="true"
fi

REPORT_CREATED_DURING_TASK="false"
if [ "$REPORT_EXISTS" = "true" ] && [ "${REPORT_MTIME:-0}" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

# Also check Slicer's markup summary
SLICER_SUMMARY="$BRATS_DIR/slicer_markups_summary.json"
if [ -f "$SLICER_SUMMARY" ]; then
    echo "Found Slicer markups summary"
    cat "$SLICER_SUMMARY"
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy ground truth for verification
cp "/tmp/ground_truth_geometry.json" /tmp/gt_geometry.json 2>/dev/null || true
chmod 644 /tmp/gt_geometry.json 2>/dev/null || true

# Copy agent outputs for verification
if [ -f "$OUTPUT_CENTROID" ]; then
    cp "$OUTPUT_CENTROID" /tmp/agent_centroid.json 2>/dev/null || true
    chmod 644 /tmp/agent_centroid.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

if [ -f "$SLICER_SUMMARY" ]; then
    cp "$SLICER_SUMMARY" /tmp/agent_slicer_summary.json 2>/dev/null || true
    chmod 644 /tmp/agent_slicer_summary.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "centroid_file_exists": $CENTROID_EXISTS,
    "centroid_file_path": "$CENTROID_PATH",
    "centroid_created_during_task": $CENTROID_CREATED_DURING_TASK,
    "centroid_ras_str": "$CENTROID_RAS",
    "report_file_exists": $REPORT_EXISTS,
    "report_file_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "screenshot_exists": $([ -f "/tmp/principal_axis_final.png" ] && echo "true" || echo "false"),
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/principal_axis_result.json 2>/dev/null || sudo rm -f /tmp/principal_axis_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/principal_axis_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/principal_axis_result.json
chmod 666 /tmp/principal_axis_result.json 2>/dev/null || sudo chmod 666 /tmp/principal_axis_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/principal_axis_result.json
echo ""
echo "=== Export Complete ==="