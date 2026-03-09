#!/bin/bash
echo "=== Exporting Registration Checkerboard QA Result ==="

source /workspace/scripts/task_utils.sh

EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_SCREENSHOT="$EXPORTS_DIR/registration_qa_checkerboard.png"
OUTPUT_REPORT="$EXPORTS_DIR/registration_qa_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot of Slicer state
echo "Capturing final screenshot..."
take_screenshot /tmp/checkerboard_final.png ga
sleep 1

# ============================================================
# Check for user-saved screenshot
# ============================================================
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k "$OUTPUT_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
    
    # Check if created during task
    SCREENSHOT_MTIME=$(stat -c %Y "$OUTPUT_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    
    echo "Found screenshot: $OUTPUT_SCREENSHOT (${SCREENSHOT_SIZE_KB}KB)"
    
    # Copy to /tmp for verification
    cp "$OUTPUT_SCREENSHOT" /tmp/user_checkerboard_screenshot.png 2>/dev/null || true
else
    echo "Screenshot not found at expected location: $OUTPUT_SCREENSHOT"
    
    # Search for any recent screenshots
    RECENT_SCREENSHOT=$(find "$EXPORTS_DIR" /home/ga -maxdepth 3 -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$RECENT_SCREENSHOT" ]; then
        echo "Found recent screenshot: $RECENT_SCREENSHOT"
        cp "$RECENT_SCREENSHOT" /tmp/user_checkerboard_screenshot.png 2>/dev/null || true
        SCREENSHOT_EXISTS="true"
        SCREENSHOT_SIZE_KB=$(du -k "$RECENT_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# ============================================================
# Check for user report JSON
# ============================================================
REPORT_EXISTS="false"
REPORT_VALID_JSON="false"
REPORT_HAS_REQUIRED_FIELDS="false"
REPORTED_MISALIGNMENT_DETECTED="null"
REPORTED_ALIGNMENT_QUALITY="unknown"
REPORTED_SHIFT_MM="0"

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    echo "Found report: $OUTPUT_REPORT"
    
    # Check if created during task
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    REPORT_CREATED_DURING_TASK="false"
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Validate JSON and extract values
    python3 << PYEOF
import json
import sys

report_path = "$OUTPUT_REPORT"
try:
    with open(report_path, 'r') as f:
        data = json.load(f)
    
    print("VALID_JSON=true")
    
    # Check required fields
    required = ["checkerboard_configured", "alignment_quality", "misalignment_detected"]
    has_required = all(k in data for k in required)
    print(f"HAS_REQUIRED={str(has_required).lower()}")
    
    # Extract values
    misalignment = data.get("misalignment_detected", None)
    print(f"MISALIGNMENT_DETECTED={str(misalignment).lower() if misalignment is not None else 'null'}")
    
    quality = data.get("alignment_quality", "unknown")
    print(f"ALIGNMENT_QUALITY={quality}")
    
    shift = data.get("estimated_shift_mm", 0)
    print(f"ESTIMATED_SHIFT={shift}")
    
    checkerboard = data.get("checkerboard_configured", False)
    print(f"CHECKERBOARD_CONFIGURED={str(checkerboard).lower()}")
    
except json.JSONDecodeError:
    print("VALID_JSON=false")
    print("HAS_REQUIRED=false")
except Exception as e:
    print(f"ERROR={e}")
    print("VALID_JSON=false")
PYEOF
    
    # Parse Python output
    REPORT_OUTPUT=$(python3 << PYEOF2
import json
try:
    with open("$OUTPUT_REPORT", 'r') as f:
        data = json.load(f)
    print(json.dumps(data))
except:
    print("{}")
PYEOF2
)
    
    REPORT_VALID_JSON=$(echo "$REPORT_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d else 'false')" 2>/dev/null || echo "false")
    
    if [ "$REPORT_VALID_JSON" = "true" ]; then
        REPORTED_MISALIGNMENT_DETECTED=$(echo "$REPORT_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('misalignment_detected', 'null')).lower())" 2>/dev/null || echo "null")
        REPORTED_ALIGNMENT_QUALITY=$(echo "$REPORT_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('alignment_quality', 'unknown'))" 2>/dev/null || echo "unknown")
        REPORTED_SHIFT_MM=$(echo "$REPORT_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('estimated_shift_mm', 0))" 2>/dev/null || echo "0")
        
        # Check for required fields
        REPORT_HAS_REQUIRED_FIELDS=$(echo "$REPORT_OUTPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
required = ['checkerboard_configured', 'alignment_quality', 'misalignment_detected']
print('true' if all(k in d for k in required) else 'false')
" 2>/dev/null || echo "false")
    fi
else
    echo "Report not found at expected location: $OUTPUT_REPORT"
fi

# ============================================================
# Check Slicer state
# ============================================================
SLICER_RUNNING="false"
VOLUMES_LOADED="false"
NUM_VOLUMES=0

if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Check window titles for evidence of work
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
SLICER_WINDOW_FOUND="false"
if echo "$WINDOWS_LIST" | grep -qi "slicer"; then
    SLICER_WINDOW_FOUND="true"
fi

# ============================================================
# Load ground truth for comparison
# ============================================================
GT_SHIFT_MM="4.0"
GT_EXPECTED_DETECTION="true"

if [ -f "$GROUND_TRUTH_DIR/registration_shift_gt.json" ]; then
    GT_SHIFT_MM=$(python3 -c "import json; print(json.load(open('$GROUND_TRUTH_DIR/registration_shift_gt.json')).get('shift_magnitude_mm', 4.0))" 2>/dev/null || echo "4.0")
    GT_EXPECTED_DETECTION=$(python3 -c "import json; print(str(json.load(open('$GROUND_TRUTH_DIR/registration_shift_gt.json')).get('expected_detection', True)).lower())" 2>/dev/null || echo "true")
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_valid_json": $REPORT_VALID_JSON,
    "report_has_required_fields": $REPORT_HAS_REQUIRED_FIELDS,
    "reported_misalignment_detected": $REPORTED_MISALIGNMENT_DETECTED,
    "reported_alignment_quality": "$REPORTED_ALIGNMENT_QUALITY",
    "reported_shift_mm": $REPORTED_SHIFT_MM,
    "ground_truth_shift_mm": $GT_SHIFT_MM,
    "ground_truth_expected_detection": $GT_EXPECTED_DETECTION,
    "final_screenshot_path": "/tmp/checkerboard_final.png",
    "user_screenshot_path": "/tmp/user_checkerboard_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/checkerboard_task_result.json 2>/dev/null || sudo rm -f /tmp/checkerboard_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/checkerboard_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/checkerboard_task_result.json
chmod 666 /tmp/checkerboard_task_result.json 2>/dev/null || sudo chmod 666 /tmp/checkerboard_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/checkerboard_task_result.json
echo ""
echo "=== Export Complete ==="