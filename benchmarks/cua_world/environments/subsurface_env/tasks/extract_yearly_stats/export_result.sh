#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Define paths
SCREENSHOT_PATH="/home/ga/Documents/yearly_stats.png"
SUMMARY_PATH="/home/ga/Documents/2011_summary.txt"
START_TIME_FILE="/tmp/task_start_time.txt"

# Get task timings
TASK_END=$(date +%s)
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")

# Check Screenshot
SS_EXISTS="false"
SS_CREATED_DURING_TASK="false"
if [ -f "$SCREENSHOT_PATH" ]; then
    SS_EXISTS="true"
    SS_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$SS_MTIME" -ge "$TASK_START" ]; then
        SS_CREATED_DURING_TASK="true"
    fi
fi

# Check Summary File
SUMMARY_EXISTS="false"
SUMMARY_CREATED_DURING_TASK="false"
SUMMARY_CONTENT='""'
if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_MTIME=$(stat -c %Y "$SUMMARY_PATH" 2>/dev/null || echo "0")
    if [ "$SUMMARY_MTIME" -ge "$TASK_START" ]; then
        SUMMARY_CREATED_DURING_TASK="true"
    fi
    
    # Safely read file content and format to JSON string
    SUMMARY_CONTENT=$(python3 -c "import json, sys; print(json.dumps(sys.stdin.read(1024)))" < "$SUMMARY_PATH" 2>/dev/null || echo '""')
fi

# Take a final screenshot of the environment state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Output the results into a JSON file for the python verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SS_EXISTS,
    "screenshot_created_during_task": $SS_CREATED_DURING_TASK,
    "summary_exists": $SUMMARY_EXISTS,
    "summary_created_during_task": $SUMMARY_CREATED_DURING_TASK,
    "summary_content": $SUMMARY_CONTENT
}
EOF

# Ensure file is readable by the agent and framework
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="