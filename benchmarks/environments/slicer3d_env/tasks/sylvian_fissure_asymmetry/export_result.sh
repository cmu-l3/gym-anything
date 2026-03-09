#!/bin/bash
echo "=== Exporting Sylvian Fissure Asymmetry Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_LEFT="$BRATS_DIR/left_sylvian.mrk.json"
OUTPUT_RIGHT="$BRATS_DIR/right_sylvian.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/sylvian_asymmetry_report.json"

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/sylvian_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any measurements from Slicer before reading files
    cat > /tmp/export_sylvian_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Get all line/ruler markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler markup(s)")

measurements = []
for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
        
        name = node.GetName().lower()
        measurement = {
            "name": node.GetName(),
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "z_position": (p1[2] + p2[2]) / 2
        }
        measurements.append(measurement)
        print(f"  {node.GetName()}: {length:.2f} mm at z={measurement['z_position']:.1f}")
        
        # Save individual markup files
        mrk_filename = f"{node.GetName().replace(' ', '_')}.mrk.json"
        mrk_path = os.path.join(output_dir, mrk_filename)
        
        # Also try to detect if this is left or right based on name or position
        if 'left' in name or 'l_' in name or name.startswith('l '):
            slicer.util.saveNode(node, os.path.join(output_dir, "left_sylvian.mrk.json"))
            print(f"    -> Saved as left_sylvian.mrk.json")
        elif 'right' in name or 'r_' in name or name.startswith('r '):
            slicer.util.saveNode(node, os.path.join(output_dir, "right_sylvian.mrk.json"))
            print(f"    -> Saved as right_sylvian.mrk.json")
        else:
            # Try to determine side from x-coordinate
            # In RAS coordinates, positive x is typically patient left
            mean_x = (p1[0] + p2[0]) / 2
            if mean_x > 0:
                slicer.util.saveNode(node, os.path.join(output_dir, "left_sylvian.mrk.json"))
                print(f"    -> Saved as left_sylvian.mrk.json (based on position)")
            else:
                slicer.util.saveNode(node, os.path.join(output_dir, "right_sylvian.mrk.json"))
                print(f"    -> Saved as right_sylvian.mrk.json (based on position)")

# Save all measurements summary
if measurements:
    summary_path = os.path.join(output_dir, "all_measurements.json")
    with open(summary_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Saved measurements summary to {summary_path}")

print("Export complete")
PYEOF
    
    # Run the export script in Slicer
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_sylvian_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# Check for measurement files
LEFT_MEAS_EXISTS="false"
LEFT_MEAS_PATH=""
LEFT_WIDTH_MM=""
LEFT_Z_POS=""

RIGHT_MEAS_EXISTS="false"
RIGHT_MEAS_PATH=""
RIGHT_WIDTH_MM=""
RIGHT_Z_POS=""

# Search for left measurement file
POSSIBLE_LEFT_PATHS=(
    "$OUTPUT_LEFT"
    "$BRATS_DIR/Left_Sylvian.mrk.json"
    "$BRATS_DIR/left.mrk.json"
    "$BRATS_DIR/L_sylvian.mrk.json"
)

for path in "${POSSIBLE_LEFT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LEFT_MEAS_EXISTS="true"
        LEFT_MEAS_PATH="$path"
        echo "Found left measurement at: $path"
        if [ "$path" != "$OUTPUT_LEFT" ]; then
            cp "$path" "$OUTPUT_LEFT" 2>/dev/null || true
        fi
        # Extract length from markup file
        LEFT_WIDTH_MM=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    # Handle Slicer markup format
    if 'markups' in data:
        for markup in data['markups']:
            if 'controlPoints' in markup and len(markup['controlPoints']) >= 2:
                p1 = markup['controlPoints'][0]['position']
                p2 = markup['controlPoints'][1]['position']
                import math
                length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                print(f'{length:.2f}')
                break
    elif 'measurements' in data:
        for m in data['measurements']:
            if m.get('length_mm'):
                print(f\"{m['length_mm']:.2f}\")
                break
except Exception as e:
    pass
" 2>/dev/null || echo "")
        break
    fi
done

# Search for right measurement file
POSSIBLE_RIGHT_PATHS=(
    "$OUTPUT_RIGHT"
    "$BRATS_DIR/Right_Sylvian.mrk.json"
    "$BRATS_DIR/right.mrk.json"
    "$BRATS_DIR/R_sylvian.mrk.json"
)

for path in "${POSSIBLE_RIGHT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        RIGHT_MEAS_EXISTS="true"
        RIGHT_MEAS_PATH="$path"
        echo "Found right measurement at: $path"
        if [ "$path" != "$OUTPUT_RIGHT" ]; then
            cp "$path" "$OUTPUT_RIGHT" 2>/dev/null || true
        fi
        # Extract length from markup file
        RIGHT_WIDTH_MM=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    if 'markups' in data:
        for markup in data['markups']:
            if 'controlPoints' in markup and len(markup['controlPoints']) >= 2:
                p1 = markup['controlPoints'][0]['position']
                p2 = markup['controlPoints'][1]['position']
                import math
                length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                print(f'{length:.2f}')
                break
    elif 'measurements' in data:
        for m in data['measurements']:
            if m.get('length_mm'):
                print(f\"{m['length_mm']:.2f}\")
                break
except Exception as e:
    pass
" 2>/dev/null || echo "")
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_LEFT=""
REPORTED_RIGHT=""
REPORTED_SFAI=""
REPORTED_CLASSIFICATION=""
REPORTED_WIDER_SIDE=""
REPORTED_LEVEL=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/sylvian_report.json"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/sylvian_asymmetry_report.json"
    "/home/ga/sylvian_asymmetry_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        # Extract report fields
        REPORTED_LEFT=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('left_width_mm', ''))" 2>/dev/null || echo "")
        REPORTED_RIGHT=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('right_width_mm', ''))" 2>/dev/null || echo "")
        REPORTED_SFAI=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('asymmetry_index_percent', ''))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', ''))" 2>/dev/null || echo "")
        REPORTED_WIDER_SIDE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('wider_side', ''))" 2>/dev/null || echo "")
        REPORTED_LEVEL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('measurement_level', ''))" 2>/dev/null || echo "")
        break
    fi
done

# If we have measurement values from markups but no report, use those
if [ -z "$REPORTED_LEFT" ] && [ -n "$LEFT_WIDTH_MM" ]; then
    REPORTED_LEFT="$LEFT_WIDTH_MM"
fi
if [ -z "$REPORTED_RIGHT" ] && [ -n "$RIGHT_WIDTH_MM" ]; then
    REPORTED_RIGHT="$RIGHT_WIDTH_MM"
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_sylvian_gt.json" /tmp/sylvian_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/sylvian_ground_truth.json 2>/dev/null || true

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
    "left_measurement_exists": $LEFT_MEAS_EXISTS,
    "left_measurement_path": "$LEFT_MEAS_PATH",
    "left_width_mm": "$LEFT_WIDTH_MM",
    "right_measurement_exists": $RIGHT_MEAS_EXISTS,
    "right_measurement_path": "$RIGHT_MEAS_PATH",
    "right_width_mm": "$RIGHT_WIDTH_MM",
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_left_width_mm": "$REPORTED_LEFT",
    "reported_right_width_mm": "$REPORTED_RIGHT",
    "reported_asymmetry_index": "$REPORTED_SFAI",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_wider_side": "$REPORTED_WIDER_SIDE",
    "reported_level": "$REPORTED_LEVEL",
    "screenshot_exists": $([ -f "/tmp/sylvian_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/sylvian_ground_truth.json" ] && echo "true" || echo "false"),
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/sylvian_task_result.json 2>/dev/null || sudo rm -f /tmp/sylvian_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/sylvian_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/sylvian_task_result.json
chmod 666 /tmp/sylvian_task_result.json 2>/dev/null || sudo chmod 666 /tmp/sylvian_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/sylvian_task_result.json
echo ""
echo "=== Export Complete ==="