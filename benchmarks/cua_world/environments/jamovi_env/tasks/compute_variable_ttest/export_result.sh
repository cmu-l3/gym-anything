#!/bin/bash
echo "=== Exporting compute_variable_ttest results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OMV_PATH="/home/ga/Documents/Jamovi/BFI25_Agreeableness.omv"
RESULTS_PATH="/home/ga/Documents/Jamovi/agreeableness_results.txt"
GROUND_TRUTH_PATH="/tmp/ground_truth.json"

# Check .omv file
OMV_EXISTS="false"
OMV_CREATED_DURING="false"
OMV_SIZE=0

if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c%s "$OMV_PATH")
    OMV_MTIME=$(stat -c%Y "$OMV_PATH")
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING="true"
    fi
fi

# Check results text file
TXT_EXISTS="false"
TXT_CONTENT=""
if [ -f "$RESULTS_PATH" ]; then
    TXT_EXISTS="true"
    # Read first 10 lines max to avoid huge files
    TXT_CONTENT=$(head -n 10 "$RESULTS_PATH" | base64 -w 0)
fi

# Check if Jamovi is running
APP_RUNNING="false"
if pgrep -f "jamovi" > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Read Ground Truth
GROUND_TRUTH="{}"
if [ -f "$GROUND_TRUTH_PATH" ]; then
    GROUND_TRUTH=$(cat "$GROUND_TRUTH_PATH")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING,
    "omv_size_bytes": $OMV_SIZE,
    "txt_exists": $TXT_EXISTS,
    "txt_content_base64": "$TXT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "ground_truth": $GROUND_TRUTH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="