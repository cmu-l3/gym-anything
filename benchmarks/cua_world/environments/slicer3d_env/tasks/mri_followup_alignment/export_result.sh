#!/bin/bash
echo "=== Exporting MRI Follow-up Alignment Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_REGISTERED="$BRATS_DIR/followup_registered.nii.gz"
OUTPUT_TRANSFORM="$BRATS_DIR/followup_transform.h5"
OUTPUT_REPORT="$BRATS_DIR/followup_report.json"

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any unsaved data from Slicer
    cat > /tmp/export_registration_data.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

print("Checking for registration outputs in Slicer scene...")

# Check for transform nodes
transform_nodes = slicer.util.getNodesByClass("vtkMRMLLinearTransformNode")
print(f"Found {len(transform_nodes)} linear transform(s)")

for node in transform_nodes:
    name = node.GetName()
    print(f"  Transform: {name}")
    # Save if it looks like a registration transform
    if "registration" in name.lower() or "followup" in name.lower() or "output" in name.lower():
        transform_path = os.path.join(output_dir, "followup_transform.h5")
        slicer.util.saveNode(node, transform_path)
        print(f"    Saved to: {transform_path}")

# Check for resampled/registered volumes
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
print(f"Found {len(volume_nodes)} volume(s)")

for node in volume_nodes:
    name = node.GetName()
    print(f"  Volume: {name}")
    # Look for registered/resampled volumes
    if "registered" in name.lower() or "resampled" in name.lower() or "output" in name.lower():
        vol_path = os.path.join(output_dir, "followup_registered.nii.gz")
        slicer.util.saveNode(node, vol_path)
        print(f"    Saved to: {vol_path}")

# Check for line measurements
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

measurements = []
import math
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
        print(f"  Line '{node.GetName()}': {length:.2f} mm")

if measurements:
    meas_path = os.path.join(output_dir, "measurements.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Measurements saved to: {meas_path}")

print("Export complete")
PYEOF
    
    # Run export script
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_registration_data.py > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# Check if registered volume exists
REGISTERED_EXISTS="false"
REGISTERED_SIZE=0
REGISTERED_MTIME=0

POSSIBLE_REG_PATHS=(
    "$OUTPUT_REGISTERED"
    "$BRATS_DIR/followup_registered.nii"
    "$BRATS_DIR/registered.nii.gz"
    "$BRATS_DIR/output_volume.nii.gz"
)

for path in "${POSSIBLE_REG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REGISTERED_EXISTS="true"
        REGISTERED_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        REGISTERED_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found registered volume: $path ($REGISTERED_SIZE bytes)"
        if [ "$path" != "$OUTPUT_REGISTERED" ]; then
            cp "$path" "$OUTPUT_REGISTERED" 2>/dev/null || true
        fi
        break
    fi
done

# Check if file was created during task
REGISTERED_CREATED_DURING_TASK="false"
if [ "$REGISTERED_EXISTS" = "true" ] && [ "$REGISTERED_MTIME" -gt "$TASK_START" ]; then
    REGISTERED_CREATED_DURING_TASK="true"
fi

# Check if transform file exists
TRANSFORM_EXISTS="false"
TRANSFORM_SIZE=0
TRANSFORM_MTIME=0

POSSIBLE_TRANSFORM_PATHS=(
    "$OUTPUT_TRANSFORM"
    "$BRATS_DIR/followup_transform.tfm"
    "$BRATS_DIR/transform.h5"
    "$BRATS_DIR/registration_transform.h5"
)

for path in "${POSSIBLE_TRANSFORM_PATHS[@]}"; do
    if [ -f "$path" ]; then
        TRANSFORM_EXISTS="true"
        TRANSFORM_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        TRANSFORM_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found transform: $path ($TRANSFORM_SIZE bytes)"
        if [ "$path" != "$OUTPUT_TRANSFORM" ]; then
            cp "$path" "$OUTPUT_TRANSFORM" 2>/dev/null || true
        fi
        break
    fi
done

TRANSFORM_CREATED_DURING_TASK="false"
if [ "$TRANSFORM_EXISTS" = "true" ] && [ "$TRANSFORM_MTIME" -gt "$TASK_START" ]; then
    TRANSFORM_CREATED_DURING_TASK="true"
fi

# Check if report exists
REPORT_EXISTS="false"
BASELINE_DIAMETER=""
FOLLOWUP_DIAMETER=""
PERCENT_CHANGE=""
REGISTRATION_VERIFIED=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/followup_report.txt"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        # Try to extract values
        if [[ "$path" == *.json ]]; then
            BASELINE_DIAMETER=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('baseline_diameter_mm', ''))" 2>/dev/null || echo "")
            FOLLOWUP_DIAMETER=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('followup_diameter_mm', ''))" 2>/dev/null || echo "")
            PERCENT_CHANGE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('percent_change', ''))" 2>/dev/null || echo "")
            REGISTRATION_VERIFIED=$(python3 -c "import json; d=json.load(open('$path')); print(str(d.get('registration_verified', '')).lower())" 2>/dev/null || echo "")
        fi
        break
    fi
done

# Check for measurement markups
MEASUREMENT_COUNT=0
if [ -f "$BRATS_DIR/measurements.json" ]; then
    MEASUREMENT_COUNT=$(python3 -c "import json; d=json.load(open('$BRATS_DIR/measurements.json')); print(len(d.get('measurements', [])))" 2>/dev/null || echo "0")
fi

# Also check for .mrk.json files
MRK_COUNT=$(find "$BRATS_DIR" -name "*.mrk.json" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)
if [ "$MRK_COUNT" -gt "$MEASUREMENT_COUNT" ]; then
    MEASUREMENT_COUNT="$MRK_COUNT"
fi

# Copy files needed for verification
echo "Copying files for verification..."

# Copy ground truth
cp "$GROUND_TRUTH_DIR/followup_gt.json" /tmp/followup_gt.json 2>/dev/null || true
chmod 644 /tmp/followup_gt.json 2>/dev/null || true

# Copy baseline for metrics computation
BASELINE_FLAIR="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz"
cp "$BASELINE_FLAIR" /tmp/baseline_flair.nii.gz 2>/dev/null || true
chmod 644 /tmp/baseline_flair.nii.gz 2>/dev/null || true

# Copy registered volume
if [ -f "$OUTPUT_REGISTERED" ]; then
    cp "$OUTPUT_REGISTERED" /tmp/followup_registered.nii.gz 2>/dev/null || true
    chmod 644 /tmp/followup_registered.nii.gz 2>/dev/null || true
fi

# Copy transform
if [ -f "$OUTPUT_TRANSFORM" ]; then
    cp "$OUTPUT_TRANSFORM" /tmp/followup_transform.h5 2>/dev/null || true
    chmod 644 /tmp/followup_transform.h5 2>/dev/null || true
fi

# Copy report
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/followup_report.json 2>/dev/null || true
    chmod 644 /tmp/followup_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "registered_volume_exists": $REGISTERED_EXISTS,
    "registered_volume_size_bytes": $REGISTERED_SIZE,
    "registered_created_during_task": $REGISTERED_CREATED_DURING_TASK,
    "transform_file_exists": $TRANSFORM_EXISTS,
    "transform_file_size_bytes": $TRANSFORM_SIZE,
    "transform_created_during_task": $TRANSFORM_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "baseline_diameter_mm": "$BASELINE_DIAMETER",
    "followup_diameter_mm": "$FOLLOWUP_DIAMETER",
    "percent_change": "$PERCENT_CHANGE",
    "registration_verified": "$REGISTRATION_VERIFIED",
    "measurement_count": $MEASUREMENT_COUNT,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/followup_alignment_result.json 2>/dev/null || sudo rm -f /tmp/followup_alignment_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/followup_alignment_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/followup_alignment_result.json
chmod 666 /tmp/followup_alignment_result.json 2>/dev/null || sudo chmod 666 /tmp/followup_alignment_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/followup_alignment_result.json
echo ""
echo "=== Export Complete ==="