#!/bin/bash
echo "=== Exporting Stereotactic Biopsy Planning Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

OUTPUT_TARGET="$BRATS_DIR/biopsy_target.mrk.json"
OUTPUT_ENTRY="$BRATS_DIR/biopsy_entry.mrk.json"
OUTPUT_TRAJECTORY="$BRATS_DIR/biopsy_trajectory.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/trajectory_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/trajectory_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any markups from Slicer before checking files
    cat > /tmp/export_trajectory_markups.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

print("Exporting trajectory planning markups...")

# Export fiducial markups
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    name = node.GetName().lower()
    n_points = node.GetNumberOfControlPoints()
    
    if n_points > 0:
        # Get first control point position
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, pos)
        
        # Determine output path based on name
        if 'target' in name:
            out_path = os.path.join(output_dir, "biopsy_target.mrk.json")
        elif 'entry' in name:
            out_path = os.path.join(output_dir, "biopsy_entry.mrk.json")
        else:
            out_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        
        # Save using Slicer's built-in method
        slicer.util.saveNode(node, out_path)
        print(f"  Saved {node.GetName()} to {out_path}")

# Export line markups (trajectory)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line node(s)")

for node in line_nodes:
    name = node.GetName().lower()
    n_points = node.GetNumberOfControlPoints()
    
    if n_points >= 2:
        if 'trajector' in name or 'path' in name or 'line' in name:
            out_path = os.path.join(output_dir, "biopsy_trajectory.mrk.json")
        else:
            out_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        
        slicer.util.saveNode(node, out_path)
        print(f"  Saved {node.GetName()} to {out_path}")

print("Markup export complete")
PYEOF

    # Run export script in background Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_trajectory_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_trajectory_markups" 2>/dev/null || true
fi

# Function to extract coordinates from Slicer markup JSON
extract_coords_from_markup() {
    local file="$1"
    python3 << PYEOF
import json
try:
    with open("$file", 'r') as f:
        data = json.load(f)
    if 'markups' in data and len(data['markups']) > 0:
        markup = data['markups'][0]
        if 'controlPoints' in markup and len(markup['controlPoints']) > 0:
            pos = markup['controlPoints'][0].get('position', [0,0,0])
            print(json.dumps(pos))
        else:
            print("null")
    else:
        print("null")
except Exception as e:
    print("null")
PYEOF
}

# Check for output files
TARGET_EXISTS="false"
ENTRY_EXISTS="false"
TRAJECTORY_EXISTS="false"
REPORT_EXISTS="false"

TARGET_COORDS="null"
ENTRY_COORDS="null"

# Search for target markup
POSSIBLE_TARGET_PATHS=(
    "$OUTPUT_TARGET"
    "$BRATS_DIR/target.mrk.json"
    "$BRATS_DIR/Target.mrk.json"
    "$BRATS_DIR/biopsy_target.json"
)

for path in "${POSSIBLE_TARGET_PATHS[@]}"; do
    if [ -f "$path" ]; then
        TARGET_EXISTS="true"
        echo "Found target markup: $path"
        [ "$path" != "$OUTPUT_TARGET" ] && cp "$path" "$OUTPUT_TARGET" 2>/dev/null || true
        TARGET_COORDS=$(extract_coords_from_markup "$OUTPUT_TARGET")
        break
    fi
done

# Search for entry markup
POSSIBLE_ENTRY_PATHS=(
    "$OUTPUT_ENTRY"
    "$BRATS_DIR/entry.mrk.json"
    "$BRATS_DIR/Entry.mrk.json"
    "$BRATS_DIR/biopsy_entry.json"
)

for path in "${POSSIBLE_ENTRY_PATHS[@]}"; do
    if [ -f "$path" ]; then
        ENTRY_EXISTS="true"
        echo "Found entry markup: $path"
        [ "$path" != "$OUTPUT_ENTRY" ] && cp "$path" "$OUTPUT_ENTRY" 2>/dev/null || true
        ENTRY_COORDS=$(extract_coords_from_markup "$OUTPUT_ENTRY")
        break
    fi
done

# Search for trajectory markup
POSSIBLE_TRAJ_PATHS=(
    "$OUTPUT_TRAJECTORY"
    "$BRATS_DIR/trajectory.mrk.json"
    "$BRATS_DIR/Trajectory.mrk.json"
    "$BRATS_DIR/line.mrk.json"
    "$BRATS_DIR/path.mrk.json"
)

for path in "${POSSIBLE_TRAJ_PATHS[@]}"; do
    if [ -f "$path" ]; then
        TRAJECTORY_EXISTS="true"
        echo "Found trajectory markup: $path"
        [ "$path" != "$OUTPUT_TRAJECTORY" ] && cp "$path" "$OUTPUT_TRAJECTORY" 2>/dev/null || true
        break
    fi
done

# Search for report
POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/trajectory_report.txt"
    "/home/ga/Documents/trajectory_report.json"
)

REPORT_DATA="{}"
for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report: $path"
        [ "$path" != "$OUTPUT_REPORT" ] && cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        REPORT_DATA=$(cat "$OUTPUT_REPORT" 2>/dev/null || echo "{}")
        break
    fi
done

# Get task timing for anti-gaming check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ELAPSED=$((TASK_END - TASK_START))

# Check if files were created during task
TARGET_CREATED_DURING_TASK="false"
ENTRY_CREATED_DURING_TASK="false"
TRAJECTORY_CREATED_DURING_TASK="false"

if [ "$TARGET_EXISTS" = "true" ]; then
    TARGET_MTIME=$(stat -c %Y "$OUTPUT_TARGET" 2>/dev/null || echo "0")
    [ "$TARGET_MTIME" -gt "$TASK_START" ] && TARGET_CREATED_DURING_TASK="true"
fi

if [ "$ENTRY_EXISTS" = "true" ]; then
    ENTRY_MTIME=$(stat -c %Y "$OUTPUT_ENTRY" 2>/dev/null || echo "0")
    [ "$ENTRY_MTIME" -gt "$TASK_START" ] && ENTRY_CREATED_DURING_TASK="true"
fi

if [ "$TRAJECTORY_EXISTS" = "true" ]; then
    TRAJ_MTIME=$(stat -c %Y "$OUTPUT_TRAJECTORY" 2>/dev/null || echo "0")
    [ "$TRAJ_MTIME" -gt "$TASK_START" ] && TRAJECTORY_CREATED_DURING_TASK="true"
fi

# Copy ground truth files for verifier
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_trajectory_gt.json" /tmp/trajectory_ground_truth.json 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" /tmp/ground_truth_seg.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_edema_dt.npy" /tmp/edema_distance_transform.npy 2>/dev/null || true
chmod 644 /tmp/trajectory_ground_truth.json /tmp/ground_truth_seg.nii.gz /tmp/edema_distance_transform.npy 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "target_markup_exists": $TARGET_EXISTS,
    "entry_markup_exists": $ENTRY_EXISTS,
    "trajectory_markup_exists": $TRAJECTORY_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "target_created_during_task": $TARGET_CREATED_DURING_TASK,
    "entry_created_during_task": $ENTRY_CREATED_DURING_TASK,
    "trajectory_created_during_task": $TRAJECTORY_CREATED_DURING_TASK,
    "target_coordinates_ras": $TARGET_COORDS,
    "entry_coordinates_ras": $ENTRY_COORDS,
    "report_data": $REPORT_DATA,
    "sample_id": "$SAMPLE_ID",
    "task_elapsed_seconds": $ELAPSED,
    "screenshot_exists": $([ -f "/tmp/trajectory_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/trajectory_task_result.json 2>/dev/null || sudo rm -f /tmp/trajectory_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/trajectory_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/trajectory_task_result.json
chmod 666 /tmp/trajectory_task_result.json 2>/dev/null || sudo chmod 666 /tmp/trajectory_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/trajectory_task_result.json
echo ""
echo "=== Export Complete ==="