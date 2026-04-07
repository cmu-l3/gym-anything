#!/bin/bash
# Export script for openvsp_forward_swept_transport task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting result for openvsp_forward_swept_transport ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application was running
APP_RUNNING=$(pgrep -f "$OPENVSP_BIN" > /dev/null && echo "true" || echo "false")

# Kill OpenVSP to ensure files are fully written
kill_openvsp

OUTPUT_PATH="/home/ga/Documents/OpenVSP/eCRM001_fsw.vsp3"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_MTIME="0"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# Write metadata to JSON (Verifier will use copy_from_env to get the actual .vsp3 files)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "app_was_running": $APP_RUNNING
}
EOF

# Move to standard location
rm -f /tmp/openvsp_fsw_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/openvsp_fsw_result.json
chmod 666 /tmp/openvsp_fsw_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/openvsp_fsw_result.json
echo "=== Export complete ==="