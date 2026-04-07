#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sabermetric Batting Analysis Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot showing what the agent was working on
take_screenshot /tmp/task_final_state.png ga
sleep 1

# Try to trigger a save just in case, though agent is required to Save As XLSX
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

# Force kill if still running
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

sleep 1

EXPECTED_OUTPUT="/home/ga/Documents/Spreadsheets/batting_analysis_2023.xlsx"

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_OUTPUT" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Output file found: $EXPECTED_OUTPUT ($FILE_SIZE bytes)"
else
    echo "Output file not found at expected location!"
    # Check if they saved it elsewhere
    ALT_FILES=$(find /home/ga/Documents -name "*.xlsx" -mmin -60 2>/dev/null || true)
    if [ -n "$ALT_FILES" ]; then
        echo "Found alternatively named/located XLSX files:"
        echo "$ALT_FILES"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "expected_path": "$EXPECTED_OUTPUT",
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Make available to host
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Results saved to /tmp/task_result.json"