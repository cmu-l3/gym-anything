#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Interactive Menu Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/Presentations/orientation_kiosk_interactive.odp"

# 1. Attempt to save if the agent hasn't (safety net, though agent should save)
# We don't want to force save if they saved with a different name, but let's try Ctrl+S if the specific file doesn't exist yet
if [ ! -f "$TARGET_FILE" ]; then
    echo "Target file not found, attempting generic save..."
    wid=$(get_impress_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        # Ctrl+Shift+S (Save As) might be safer but complex to automate filename entry
        # We'll just rely on the verification checking file existence
    fi
fi

# 2. Check for output file
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$TARGET_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "target_path": "$TARGET_FILE"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export completed to /tmp/task_result.json"