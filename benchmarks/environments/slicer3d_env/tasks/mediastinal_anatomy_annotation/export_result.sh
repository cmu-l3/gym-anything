#!/bin/bash
echo "=== Exporting Mediastinal Anatomy Annotation Results ==="

# Source common utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DURATION=$((TASK_END - TASK_START))

# Get patient ID
PATIENT_ID=$(cat /tmp/lidc_patient_id 2>/dev/null || echo "LIDC-IDRI-0001")

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
LANDMARKS_FILE="$LIDC_DIR/mediastinal_landmarks.mrk.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# ============================================================
# Try to export landmarks from Slicer if running
# ============================================================
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Attempting to export landmarks from Slicer..."
    
    cat > /tmp/export_landmarks.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/LIDC"
output_file = os.path.join(output_dir, "mediastinal_landmarks.mrk.json")

os.makedirs(output_dir, exist_ok=True)

# Get all fiducial nodes
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fiducial_nodes)} fiducial node(s)")

all_landmarks = []
for node in fiducial_nodes:
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node.GetName()}' has {n_points} control points")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        
        all_landmarks.append({
            "label": label,
            "position": pos,
            "node_name": node.GetName()
        })
        print(f"    Point {i}: '{label}' at {pos}")

# Save in Slicer markup format
if fiducial_nodes:
    # Save the first fiducial node
    node = fiducial_nodes[0]
    slicer.util.saveNode(node, output_file)
    print(f"Saved landmarks to {output_file}")
elif all_landmarks:
    # Create a simple JSON if no Slicer save
    with open(output_file.replace('.mrk.json', '_manual.json'), 'w') as f:
        json.dump({"landmarks": all_landmarks}, f, indent=2)

print("Export complete")
PYEOF

    # Run export in background Slicer instance
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_landmarks.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# ============================================================
# Check for landmarks file
# ============================================================
LANDMARKS_EXIST="false"
LANDMARKS_COUNT=0
LANDMARKS_PATH=""

# Check possible locations
POSSIBLE_PATHS=(
    "$LANDMARKS_FILE"
    "$LIDC_DIR/F.mrk.json"
    "$LIDC_DIR/Fiducial.mrk.json"
    "$LIDC_DIR/MarkupsFiducial.mrk.json"
    "/home/ga/Documents/mediastinal_landmarks.mrk.json"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LANDMARKS_EXIST="true"
        LANDMARKS_PATH="$path"
        echo "Found landmarks file at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$LANDMARKS_FILE" ]; then
            cp "$path" "$LANDMARKS_FILE" 2>/dev/null || true
        fi
        break
    fi
done

# Count landmarks if file exists
if [ "$LANDMARKS_EXIST" = "true" ] && [ -f "$LANDMARKS_PATH" ]; then
    LANDMARKS_COUNT=$(python3 -c "
import json
try:
    with open('$LANDMARKS_PATH', 'r') as f:
        data = json.load(f)
    # Slicer markup format
    if 'markups' in data and len(data['markups']) > 0:
        count = len(data['markups'][0].get('controlPoints', []))
    elif 'landmarks' in data:
        count = len(data['landmarks'])
    else:
        count = 0
    print(count)
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")
    echo "Landmark count: $LANDMARKS_COUNT"
fi

# Check file modification time
FILE_CREATED_DURING_TASK="false"
if [ "$LANDMARKS_EXIST" = "true" ] && [ -f "$LANDMARKS_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$LANDMARKS_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "File was created during task"
    else
        echo "WARNING: File existed before task started"
    fi
fi

# ============================================================
# Copy files for verification
# ============================================================
echo "Preparing files for verification..."

# Copy ground truth
if [ -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_mediastinal_gt.json" ]; then
    cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_mediastinal_gt.json" /tmp/mediastinal_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/mediastinal_ground_truth.json 2>/dev/null || true
fi

# Copy agent landmarks
if [ -f "$LANDMARKS_FILE" ]; then
    cp "$LANDMARKS_FILE" /tmp/agent_landmarks.mrk.json 2>/dev/null || true
    chmod 644 /tmp/agent_landmarks.mrk.json 2>/dev/null || true
fi

# Copy CT file path info for HU validation
CT_FILE=""
if [ -f "$LIDC_DIR/$PATIENT_ID/chest_ct.nii.gz" ]; then
    CT_FILE="$LIDC_DIR/$PATIENT_ID/chest_ct.nii.gz"
    cp "$CT_FILE" /tmp/chest_ct.nii.gz 2>/dev/null || true
    chmod 644 /tmp/chest_ct.nii.gz 2>/dev/null || true
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_id": "$PATIENT_ID",
    "slicer_running": $SLICER_RUNNING,
    "landmarks_file_exists": $LANDMARKS_EXIST,
    "landmarks_file_path": "$LANDMARKS_PATH",
    "landmarks_count": $LANDMARKS_COUNT,
    "expected_landmarks_count": 6,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $DURATION,
    "screenshot_exists": $([ -f /tmp/task_final_screenshot.png ] && echo "true" || echo "false"),
    "ct_file": "$CT_FILE",
    "ground_truth_available": $([ -f /tmp/mediastinal_ground_truth.json ] && echo "true" || echo "false")
}
EOF

# Move to final location
rm -f /tmp/mediastinal_task_result.json 2>/dev/null || sudo rm -f /tmp/mediastinal_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/mediastinal_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/mediastinal_task_result.json
chmod 666 /tmp/mediastinal_task_result.json 2>/dev/null || sudo chmod 666 /tmp/mediastinal_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/mediastinal_task_result.json"
cat /tmp/mediastinal_task_result.json
echo ""
echo "=== Export Complete ==="