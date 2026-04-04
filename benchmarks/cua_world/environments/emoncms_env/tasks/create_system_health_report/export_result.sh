#!/bin/bash
# export_result.sh — Export results for system health report task
# Gathers agent output and ground truth into a single JSON for the python verifier.

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

REPORT_FILE="/home/ga/system_health_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# check file existence and metadata
# -----------------------------------------------------------------------
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely (escape quotes/backslashes for JSON)
    # limit size to 2KB to prevent issues
    REPORT_CONTENT=$(head -c 2048 "$REPORT_FILE" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))')
else
    REPORT_CONTENT="\"\""
fi

# -----------------------------------------------------------------------
# Load Ground Truth
# -----------------------------------------------------------------------
GROUND_TRUTH="{}"
if [ -f "/tmp/ground_truth.json" ]; then
    GROUND_TRUTH=$(cat /tmp/ground_truth.json)
fi

# -----------------------------------------------------------------------
# Create Result JSON
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content_raw": $REPORT_CONTENT,
    "ground_truth": $GROUND_TRUTH,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s)
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result JSON:"
cat /tmp/task_result.json