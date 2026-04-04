#!/bin/bash
echo "=== Exporting Tumor-to-Vessel Distance Measurement Result ==="

source /workspace/scripts/task_utils.sh

EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$EXPORTS_DIR/tumor_vessel_distance.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/tvd_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Check for output file
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
VALID_JSON="false"
REPORTED_DISTANCE=""
REPORTED_RESECTABLE=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Output file was created during task"
    else
        echo "WARNING: Output file exists but was not created during task"
    fi
    
    # Validate JSON and extract values
    PARSE_RESULT=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/Documents/SlicerData/Exports/tumor_vessel_distance.json", "r") as f:
        data = json.load(f)
    
    # Check for required fields
    has_distance = "minimum_distance_mm" in data
    has_resectable = "safely_resectable" in data
    
    if has_distance and has_resectable:
        distance = float(data["minimum_distance_mm"])
        resectable = bool(data["safely_resectable"])
        
        # Validate distance is in reasonable range
        if 0.01 <= distance <= 200:
            print(f"VALID|{distance:.4f}|{str(resectable).lower()}")
        else:
            print(f"INVALID_RANGE|{distance:.4f}|{str(resectable).lower()}")
    else:
        print("MISSING_FIELDS||")
        
except json.JSONDecodeError as e:
    print(f"PARSE_ERROR||")
except Exception as e:
    print(f"ERROR||")
PYEOF
)
    
    IFS='|' read -r PARSE_STATUS REPORTED_DISTANCE REPORTED_RESECTABLE <<< "$PARSE_RESULT"
    
    if [ "$PARSE_STATUS" = "VALID" ] || [ "$PARSE_STATUS" = "INVALID_RANGE" ]; then
        VALID_JSON="true"
        echo "Parsed distance: $REPORTED_DISTANCE mm"
        echo "Parsed resectability: $REPORTED_RESECTABLE"
    else
        echo "JSON parsing issue: $PARSE_STATUS"
    fi
else
    echo "Output file not found at: $OUTPUT_FILE"
    
    # Check if user saved somewhere else
    echo "Searching for result file in common locations..."
    ALTERNATE_FILES=$(find /home/ga -name "*tumor*distance*.json" -o -name "*vessel*distance*.json" 2>/dev/null | head -3)
    if [ -n "$ALTERNATE_FILES" ]; then
        echo "Found potential alternate files:"
        echo "$ALTERNATE_FILES"
    fi
fi

# Load ground truth for comparison
GT_DISTANCE=""
GT_RESECTABLE=""
GT_JSON="/tmp/tvd_ground_truth.json"

if [ -f "$GT_JSON" ]; then
    GT_VALUES=$(python3 << 'PYEOF'
import json
try:
    with open("/tmp/tvd_ground_truth.json", "r") as f:
        data = json.load(f)
    distance = data.get("min_tumor_portal_distance_mm", 0)
    resectable = distance >= 10.0
    print(f"{distance:.4f}|{str(resectable).lower()}")
except Exception:
    print("|")
PYEOF
)
    IFS='|' read -r GT_DISTANCE GT_RESECTABLE <<< "$GT_VALUES"
    echo "Ground truth distance: $GT_DISTANCE mm"
    echo "Ground truth resectability: $GT_RESECTABLE"
fi

# Check screenshot exists
SCREENSHOT_EXISTS="false"
if [ -f /tmp/tvd_final.png ] && [ "$(stat -c %s /tmp/tvd_final.png 2>/dev/null || echo 0)" -gt 10000 ]; then
    SCREENSHOT_EXISTS="true"
fi

# Get patient number used
PATIENT_NUM=$(cat /tmp/ircadb_patient_num 2>/dev/null || echo "5")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "valid_json": $VALID_JSON,
    "reported_distance_mm": "$REPORTED_DISTANCE",
    "reported_resectable": "$REPORTED_RESECTABLE",
    "gt_distance_mm": "$GT_DISTANCE",
    "gt_resectable": "$GT_RESECTABLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "patient_num": "$PATIENT_NUM",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/tvd_task_result.json 2>/dev/null || sudo rm -f /tmp/tvd_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/tvd_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/tvd_task_result.json
chmod 666 /tmp/tvd_task_result.json 2>/dev/null || sudo chmod 666 /tmp/tvd_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/tvd_task_result.json:"
cat /tmp/tvd_task_result.json
echo ""
echo "=== Export Complete ==="