#!/bin/bash
echo "=== Exporting identify_alpha_channel result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/Documents/alpha_channel_result.txt"

# 1. Check Output File
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
REPORTED_VALUE=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read the first line, trim whitespace
    REPORTED_VALUE=$(head -n 1 "$OUTPUT_FILE" | tr -d '[:space:]')
fi

# 2. Check App State
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Read Ground Truth
GROUND_TRUTH=$(cat /tmp/ground_truth_alpha.txt 2>/dev/null || echo "")
GROUND_TRUTH_TOP3=$(cat /tmp/ground_truth_top3.txt 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "reported_value": "$REPORTED_VALUE",
    "ground_truth": "$GROUND_TRUTH",
    "ground_truth_top3": "$GROUND_TRUTH_TOP3",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="