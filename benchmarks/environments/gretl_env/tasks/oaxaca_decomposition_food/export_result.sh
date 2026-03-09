#!/bin/bash
set -e
echo "=== Exporting Oaxaca Decomposition Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Documents/gretl_output"
SCRIPT_FILE="$RESULTS_DIR/oaxaca_script.inp"
OUTPUT_FILE="$RESULTS_DIR/oaxaca_results.txt"

# 1. Capture Final State
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# 2. Check Agent Files
SCRIPT_EXISTS="false"
SCRIPT_CONTENT=""
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    # Read first 1000 chars of script for debugging/verification
    SCRIPT_CONTENT=$(head -c 1000 "$SCRIPT_FILE" | base64 -w 0)
fi

OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE" | base64 -w 0)
    
    # Check creation time
    F_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$F_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Retrieve Ground Truth (generated in setup)
GT_TOTAL="0"
GT_EXPL="0"
GT_UNEXPL="0"

if [ -f /tmp/ground_truth_values.txt ]; then
    source /tmp/ground_truth_values.txt
    GT_TOTAL=$TOTAL_GAP
    GT_EXPL=$EXPLAINED
    GT_UNEXPL=$UNEXPLAINED
fi

# 4. Check App Status
APP_RUNNING="false"
if pgrep -f "gretl" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Build Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "app_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "script_exists": $SCRIPT_EXISTS,
    "script_content_b64": "$SCRIPT_CONTENT",
    "output_exists": $OUTPUT_EXISTS,
    "output_content_b64": "$OUTPUT_CONTENT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "ground_truth": {
        "total_gap": $GT_TOTAL,
        "explained": $GT_EXPL,
        "unexplained": $GT_UNEXPL
    }
}
EOF

# Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="