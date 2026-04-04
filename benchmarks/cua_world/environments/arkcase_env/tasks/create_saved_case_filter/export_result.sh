#!/bin/bash
echo "=== Exporting create_saved_case_filter results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. CHECK OUTPUT FILE
OUTPUT_PATH="/home/ga/urgent_cases.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
REPORTED_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content, clean whitespace
    REPORTED_CONTENT=$(cat "$OUTPUT_PATH" | tr '\n' ',' | sed 's/,$//')
fi

# 2. GET GROUND TRUTH (Created in setup_task.sh)
HIGH_PRIORITY_IDS=$(cat /tmp/ground_truth_high.txt 2>/dev/null | tr '\n' ',' | sed 's/,$//')
LOW_PRIORITY_IDS=$(cat /tmp/ground_truth_low.txt 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# 3. CAPTURE FINAL SCREENSHOT
take_screenshot /tmp/task_final.png

# 4. CREATE RESULT JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "reported_content": "$REPORTED_CONTENT",
    "ground_truth_high": "$HIGH_PRIORITY_IDS",
    "ground_truth_low": "$LOW_PRIORITY_IDS",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="