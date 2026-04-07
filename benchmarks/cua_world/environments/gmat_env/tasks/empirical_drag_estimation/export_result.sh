#!/bin/bash
set -euo pipefail

echo "=== Exporting empirical_drag_estimation results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_FILE="/home/ga/GMAT_output/estimated_cd.txt"
SCRIPT_DIR="/home/ga/GMAT_output"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Look for GMAT scripts in output dir or documents
SCRIPT_PATH=$(find "$SCRIPT_DIR" /home/ga/Documents/missions -maxdepth 1 -name "*.script" -type f -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING="false"
SCRIPT_CONTENT=""

if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH")
    if [ "$SCRIPT_MTIME" -ge "$TASK_START" ]; then
        SCRIPT_CREATED_DURING="true"
    fi
    # Safely copy script content to an accessible location for python verifier
    cp "$SCRIPT_PATH" /tmp/agent_script.script
    chmod 666 /tmp/agent_script.script
fi

# Check for the output text file
FILE_EXISTS="false"
FILE_CREATED_DURING="false"
CD_TEXT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING="true"
    fi
    # Extract contents (first 100 bytes is enough)
    CD_TEXT=$(head -c 100 "$OUTPUT_FILE" | tr -d '\000-\031' || echo "")
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Build result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING,
    "script_path": "${SCRIPT_PATH:-}",
    "result_file_exists": $FILE_EXISTS,
    "result_created_during_task": $FILE_CREATED_DURING,
    "cd_file_content": "${CD_TEXT}"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="