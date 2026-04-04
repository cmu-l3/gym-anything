#!/bin/bash
echo "=== Exporting MANOVA results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/Jamovi/manova_results.txt"
OMV_PATH="/home/ga/Documents/Jamovi/ExamAnxiety_MANOVA.omv"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content (limit size just in case)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 4096)
fi

# Check Project File (.omv)
OMV_EXISTS="false"
OMV_SIZE="0"
if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH" 2>/dev/null || echo "0")
fi

# Check if Jamovi is still running
APP_RUNNING=$(pgrep -f "jamovi" > /dev/null && echo "true" || echo "false")

# Create JSON result
# Using python to safely encode the file content string
cat > /tmp/task_result_builder.py << PYEOF
import json
import time

result = {
    "task_start": $TASK_START,
    "task_end": int(time.time()),
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": """$REPORT_CONTENT""",
    "omv_exists": $OMV_EXISTS,
    "omv_size_bytes": $OMV_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "ground_truth_path": "/var/lib/jamovi_ground_truth/manova_expected.json"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

python3 /tmp/task_result_builder.py
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="