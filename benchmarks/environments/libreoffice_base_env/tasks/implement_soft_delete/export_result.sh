#!/bin/bash
set -e
echo "=== Exporting implement_soft_delete results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot before closing anything
take_screenshot /tmp/task_final.png

# 2. Gracefully close LibreOffice to ensure HSQLDB flushes to the ODB file
# This is CRITICAL for embedded HSQLDB - data is only written to script on save/close
echo "Closing LibreOffice to flush database changes..."
kill_libreoffice

# 3. timestamps and existence checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ODB_PATH="/home/ga/chinook.odb"

if [ -f "$ODB_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$ODB_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$ODB_PATH")
    
    # Check if modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    else
        MODIFIED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    MODIFIED_DURING_TASK="false"
fi

# 4. Create result JSON
# We don't parse the ODB here; the python verifier will do it on the host
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$ODB_PATH",
    "output_size": $OUTPUT_SIZE,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="