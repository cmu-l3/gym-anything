#!/bin/bash
set -euo pipefail

echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing Thunderbird
take_screenshot /tmp/task_final.png

# Gracefully close Thunderbird to ensure .msf and mbox files are flushed to disk
echo "Closing Thunderbird to flush state..."
close_thunderbird
sleep 3

LOCAL_MAIL_DIR="/home/ga/.thunderbird/default-release/Mail/Local Folders"
LEGAL_HOLD_PATH="${LOCAL_MAIL_DIR}/Legal_Hold"
TRASH_PATH="${LOCAL_MAIL_DIR}/Trash"

# Check if output folder was created
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"

if [ -f "$LEGAL_HOLD_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$LEGAL_HOLD_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$LEGAL_HOLD_PATH" 2>/dev/null || echo "0")
fi

# Check if application was running initially
APP_RUNNING="true"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "legal_hold_exists": $OUTPUT_EXISTS,
    "legal_hold_size_bytes": $OUTPUT_SIZE,
    "legal_hold_mtime": $OUTPUT_MTIME,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "legal_hold_path": "$LEGAL_HOLD_PATH",
    "trash_path": "$TRASH_PATH"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="