#!/bin/bash
echo "=== Exporting register_and_report_host_activity results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check for Output File
# The user might save as .csv, .txt, or .xls. We look for any matching basename.
DOCS_DIR="/home/ga/Documents"
REPORT_FILE=""
REPORT_EXISTS="false"
CREATED_DURING_TASK="false"
FILE_SIZE="0"
FILE_EXTENSION=""

# Find the most likely report file (newest matching 'james_wilson_report*')
FOUND_FILE=$(find "$DOCS_DIR" -maxdepth 1 -name "james_wilson_report.*" -type f -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$FOUND_FILE" ]; then
    REPORT_FILE="$FOUND_FILE"
    REPORT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    FILE_EXTENSION="${REPORT_FILE##*.}"
    
    # Verify it was created during the task
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    echo "Found report file: $REPORT_FILE"
else
    echo "No report file found matching 'james_wilson_report.*'"
fi

# 3. Check if App is Still Running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create Result JSON
# We copy the report file to a temp location with a known name for the verifier to pick up easily
# if it exists.
VERIFIER_REPORT_PATH="/tmp/submitted_report.dat"
if [ "$REPORT_EXISTS" = "true" ]; then
    cp "$REPORT_FILE" "$VERIFIER_REPORT_PATH"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_FILE",
    "report_extension": "$FILE_EXTENSION",
    "created_during_task": $CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "verifier_report_path": "$VERIFIER_REPORT_PATH"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="