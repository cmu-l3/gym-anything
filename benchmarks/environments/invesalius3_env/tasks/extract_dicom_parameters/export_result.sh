#!/bin/bash
set -e

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/ct_parameters.txt"
GROUND_TRUTH_PATH="/var/lib/invesalius_ground_truth/ground_truth.json"

# 1. Capture Final State
# ----------------------
take_screenshot /tmp/task_final.png

# 2. Analyze Output File
# ----------------------
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (escape quotes for JSON safety)
    # We read the raw file here; python verifier will parse it
    FILE_CONTENT=$(cat "$OUTPUT_PATH" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))')
else
    FILE_CONTENT="\"\""
fi

# 3. Read Ground Truth
# --------------------
GT_CONTENT="{}"
if [ -f "$GROUND_TRUTH_PATH" ]; then
    GT_CONTENT=$(cat "$GROUND_TRUTH_PATH")
fi

# 4. Check App Status
# -------------------
APP_RUNNING="false"
if pgrep -f "invesalius" > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
# ---------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_raw": $FILE_CONTENT,
    "ground_truth": $GT_CONTENT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="