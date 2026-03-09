#!/bin/bash
echo "=== Exporting Rib Counting and Vertebral Localization Result ==="

source /workspace/scripts/task_utils.sh

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_LANDMARKS="$LIDC_DIR/vertebral_landmarks.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/rib_count_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/rib_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Export fiducials from Slicer
    cat > /tmp/export_fiducials.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

all_fiducials = []
vertebral_landmarks = {}

# Find all fiducial nodes
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    node_name = node.GetName()
    n_points = node.GetNumberOfControlPoints()
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        
        fiducial = {
            "node_name": node_name,
            "label": label,
            "position": pos
        }
        all_fiducials.append(fiducial)
        
        # Check if this is a vertebral landmark
        label_upper = label.upper() if label else ""
        if "T1" in label_upper and "T1" not in label_upper.replace("T1", "", 1):
            vertebral_landmarks["T1"] = pos
            print(f"  T1 landmark at {pos}")
        elif "T6" in label_upper:
            vertebral_landmarks["T6"] = pos
            print(f"  T6 landmark at {pos}")
        elif "T12" in label_upper:
            vertebral_landmarks["T12"] = pos
            print(f"  T12 landmark at {pos}")

# Calculate T1-T12 distance if both exist
t1_t12_distance = None
if "T1" in vertebral_landmarks and "T12" in vertebral_landmarks:
    t1 = vertebral_landmarks["T1"]
    t12 = vertebral_landmarks["T12"]
    t1_t12_distance = math.sqrt(sum((a-b)**2 for a,b in zip(t1, t12)))
    print(f"  T1-T12 distance: {t1_t12_distance:.1f} mm")

# Save fiducials data
output = {
    "fiducials": all_fiducials,
    "vertebral_landmarks": vertebral_landmarks,
    "t1_t12_distance_mm": t1_t12_distance
}

fid_path = os.path.join(output_dir, "vertebral_landmarks.mrk.json")
with open(fid_path, "w") as f:
    json.dump(output, f, indent=2)
print(f"Exported {len(all_fiducials)} fiducials to {fid_path}")

# Also try to save the Slicer markup node directly
for node in fid_nodes:
    if node.GetName() != "Nodule":  # Don't overwrite the original nodule marker
        try:
            node_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
            slicer.util.saveNode(node, node_path)
        except:
            pass
PYEOF

    # Run the export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_fiducials.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_fiducials" 2>/dev/null || true
fi

# Check if agent saved landmark file
LANDMARKS_EXISTS="false"
LANDMARKS_PATH=""
T1_PLACED="false"
T6_PLACED="false"
T12_PLACED="false"
T1_T12_DISTANCE=""

POSSIBLE_LANDMARK_PATHS=(
    "$OUTPUT_LANDMARKS"
    "$LIDC_DIR/landmarks.mrk.json"
    "$LIDC_DIR/fiducials.mrk.json"
    "/home/ga/Documents/vertebral_landmarks.mrk.json"
)

for path in "${POSSIBLE_LANDMARK_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LANDMARKS_EXISTS="true"
        LANDMARKS_PATH="$path"
        echo "Found landmarks at: $path"
        
        # Check which landmarks are present
        if grep -qi '"T1"' "$path" 2>/dev/null; then
            T1_PLACED="true"
        fi
        if grep -qi '"T6"' "$path" 2>/dev/null; then
            T6_PLACED="true"
        fi
        if grep -qi '"T12"' "$path" 2>/dev/null; then
            T12_PLACED="true"
        fi
        
        # Extract T1-T12 distance
        T1_T12_DISTANCE=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
dist = data.get('t1_t12_distance_mm')
if dist:
    print(f'{dist:.1f}')
else:
    print('')
" 2>/dev/null || echo "")
        
        if [ "$path" != "$OUTPUT_LANDMARKS" ]; then
            cp "$path" "$OUTPUT_LANDMARKS" 2>/dev/null || true
        fi
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_NODULE_LEVEL=""
REPORTED_RIB_COUNT=""
REPORTED_VARIANTS=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/report.json"
    "$LIDC_DIR/rib_report.json"
    "/home/ga/Documents/rib_count_report.json"
    "/home/ga/rib_count_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Extract report fields
        REPORTED_NODULE_LEVEL=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(data.get('nodule_vertebral_level', ''))
" 2>/dev/null || echo "")
        
        REPORTED_RIB_COUNT=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(data.get('total_rib_pairs', ''))
" 2>/dev/null || echo "")
        
        REPORTED_VARIANTS=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
variants = data.get('anatomical_variants', {})
print(json.dumps(variants))
" 2>/dev/null || echo "{}")
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Check for file creation timestamps (anti-gaming)
LANDMARKS_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_LANDMARKS" ]; then
    LANDMARKS_MTIME=$(stat -c %Y "$OUTPUT_LANDMARKS" 2>/dev/null || echo "0")
    if [ "$LANDMARKS_MTIME" -gt "$TASK_START" ]; then
        LANDMARKS_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_vertebral_gt.json" /tmp/ground_truth_vertebral.json 2>/dev/null || true
chmod 644 /tmp/ground_truth_vertebral.json 2>/dev/null || true

# Copy agent outputs for verifier
if [ -f "$OUTPUT_LANDMARKS" ]; then
    cp "$OUTPUT_LANDMARKS" /tmp/agent_landmarks.json 2>/dev/null || true
    chmod 644 /tmp/agent_landmarks.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

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
    "landmarks_exists": $LANDMARKS_EXISTS,
    "landmarks_created_during_task": $LANDMARKS_CREATED_DURING_TASK,
    "t1_placed": $T1_PLACED,
    "t6_placed": $T6_PLACED,
    "t12_placed": $T12_PLACED,
    "t1_t12_distance_mm": "$T1_T12_DISTANCE",
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_nodule_level": "$REPORTED_NODULE_LEVEL",
    "reported_rib_count": "$REPORTED_RIB_COUNT",
    "reported_variants": $REPORTED_VARIANTS,
    "screenshot_exists": $([ -f "/tmp/rib_final.png" ] && echo "true" || echo "false"),
    "patient_id": "$PATIENT_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/rib_task_result.json 2>/dev/null || sudo rm -f /tmp/rib_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/rib_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/rib_task_result.json
chmod 666 /tmp/rib_task_result.json 2>/dev/null || sudo chmod 666 /tmp/rib_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/rib_task_result.json
echo ""
echo "=== Export Complete ==="