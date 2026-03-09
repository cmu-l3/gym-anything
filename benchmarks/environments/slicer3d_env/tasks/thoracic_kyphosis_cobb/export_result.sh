#!/bin/bash
echo "=== Exporting Thoracic Kyphosis Measurement Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
RESULT_FILE="/tmp/task_result.json"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"

# Get patient ID
if [ -f /tmp/kyphosis_patient_id ]; then
    PATIENT_ID=$(cat /tmp/kyphosis_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0003"
fi

# Record export time
EXPORT_TIME=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task started: $TASK_START"
echo "Export time: $EXPORT_TIME"

# Take final screenshot
mkdir -p "$SCREENSHOT_DIR"
FINAL_SCREENSHOT="$SCREENSHOT_DIR/kyphosis_final.png"
DISPLAY=:1 scrot "$FINAL_SCREENSHOT" 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi
echo "Slicer running: $SLICER_RUNNING"

# Check for landmark file
LANDMARKS_FILE="$LIDC_DIR/kyphosis_landmarks.mrk.json"
LANDMARKS_EXISTS="false"
LANDMARKS_VALID="false"
MARKUP_COUNT=0

# Check multiple possible locations
POSSIBLE_LANDMARK_PATHS=(
    "$LANDMARKS_FILE"
    "$LIDC_DIR/landmarks.mrk.json"
    "$LIDC_DIR/kyphosis.mrk.json"
    "$LIDC_DIR/cobb_landmarks.mrk.json"
    "/home/ga/Documents/kyphosis_landmarks.mrk.json"
)

for path in "${POSSIBLE_LANDMARK_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LANDMARKS_EXISTS="true"
        echo "Found landmarks at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$LANDMARKS_FILE" ]; then
            cp "$path" "$LANDMARKS_FILE" 2>/dev/null || true
        fi
        
        # Check if created after task start
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            LANDMARKS_VALID="true"
        fi
        
        # Count markups
        MARKUP_COUNT=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    count = 0
    # Check for markups array
    markups = data.get('markups', [])
    for m in markups:
        # Count control points for lines/rulers
        if 'controlPoints' in m:
            count += len(m.get('controlPoints', []))
        else:
            count += 1
    # Also check root level controlPoints
    if 'controlPoints' in data:
        count += len(data.get('controlPoints', []))
    print(max(count, len(markups)))
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")
        
        echo "Markup count: $MARKUP_COUNT"
        break
    fi
done

# Check for report file
REPORT_FILE="$LIDC_DIR/kyphosis_report.json"
REPORT_EXISTS="false"
REPORT_VALID="false"
AGENT_ANGLE=""
AGENT_CLASS=""
AGENT_SUP_VERT=""
AGENT_INF_VERT=""

POSSIBLE_REPORT_PATHS=(
    "$REPORT_FILE"
    "$LIDC_DIR/report.json"
    "$LIDC_DIR/cobb_report.json"
    "/home/ga/Documents/kyphosis_report.json"
    "/home/ga/kyphosis_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$REPORT_FILE" ]; then
            cp "$path" "$REPORT_FILE" 2>/dev/null || true
        fi
        
        # Check if created after task start
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            REPORT_VALID="true"
        fi
        
        # Parse report fields
        REPORT_PARSE=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    
    # Try multiple possible field names
    angle = data.get('cobb_angle_degrees', 
            data.get('cobb_angle', 
            data.get('angle_degrees',
            data.get('angle', ''))))
    
    classification = data.get('classification', 
                    data.get('class', 
                    data.get('category', '')))
    
    sup_vert = data.get('superior_vertebra',
               data.get('upper_vertebra',
               data.get('sup_vert', '')))
    
    inf_vert = data.get('inferior_vertebra',
               data.get('lower_vertebra',
               data.get('inf_vert', '')))
    
    # Output as tab-separated for easy parsing
    print(f'{angle}\t{classification}\t{sup_vert}\t{inf_vert}')
except Exception as e:
    print('\t\t\t')
" 2>/dev/null || echo "")
        
        AGENT_ANGLE=$(echo "$REPORT_PARSE" | cut -f1)
        AGENT_CLASS=$(echo "$REPORT_PARSE" | cut -f2)
        AGENT_SUP_VERT=$(echo "$REPORT_PARSE" | cut -f3)
        AGENT_INF_VERT=$(echo "$REPORT_PARSE" | cut -f4)
        
        echo "Parsed report:"
        echo "  Angle: $AGENT_ANGLE"
        echo "  Classification: $AGENT_CLASS"
        echo "  Superior: $AGENT_SUP_VERT"
        echo "  Inferior: $AGENT_INF_VERT"
        break
    fi
done

# Check for visualization screenshot
VIS_SCREENSHOT=""
AGENT_SCREENSHOTS=$(find "$LIDC_DIR" "$SCREENSHOT_DIR" /home/ga/Documents -maxdepth 2 -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | head -5)
SCREENSHOT_COUNT=$(echo "$AGENT_SCREENSHOTS" | grep -c "png" 2>/dev/null || echo "0")

if [ "$SCREENSHOT_COUNT" -gt 0 ]; then
    VIS_SCREENSHOT=$(echo "$AGENT_SCREENSHOTS" | head -1)
    echo "Found $SCREENSHOT_COUNT screenshots created during task"
fi

# Copy ground truth for verifier (hidden location)
GT_FILE="$GROUND_TRUTH_DIR/${PATIENT_ID}_kyphosis_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" /tmp/kyphosis_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/kyphosis_ground_truth.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "thoracic_kyphosis_cobb@1",
    "patient_id": "$PATIENT_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "task_start_time": $TASK_START,
    "export_time": $EXPORT_TIME,
    "landmarks_file_exists": $LANDMARKS_EXISTS,
    "landmarks_file_valid": $LANDMARKS_VALID,
    "landmarks_file_path": "$LANDMARKS_FILE",
    "markup_count": $MARKUP_COUNT,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_valid": $REPORT_VALID,
    "report_file_path": "$REPORT_FILE",
    "agent_cobb_angle": "$AGENT_ANGLE",
    "agent_classification": "$AGENT_CLASS",
    "agent_superior_vertebra": "$AGENT_SUP_VERT",
    "agent_inferior_vertebra": "$AGENT_INF_VERT",
    "visualization_screenshot": "$VIS_SCREENSHOT",
    "agent_screenshot_count": $SCREENSHOT_COUNT,
    "final_screenshot": "$FINAL_SCREENSHOT",
    "screenshot_exists": $([ -f "$FINAL_SCREENSHOT" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/kyphosis_ground_truth.json" ] && echo "true" || echo "false")
}
EOF

# Move to final location with permission handling
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="