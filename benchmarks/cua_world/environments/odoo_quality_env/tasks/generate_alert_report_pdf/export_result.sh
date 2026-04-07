#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather data for verification
DOWNLOADS_DIR="/home/ga/Downloads"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Initialize result variables
FILE_FOUND="false"
FILE_NAME=""
FILE_SIZE=0
IS_PDF="false"
CREATED_DURING_TASK="false"
FILE_PATH=""

# Find the most recently modified PDF file in Downloads
# We look for files containing "Structural" or "Quality" 
TARGET_FILE=$(find "$DOWNLOADS_DIR" -type f \( -name "*Structural*" -o -name "*Quality*" \) -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$TARGET_FILE" ]; then
    FILE_FOUND="true"
    FILE_PATH="$TARGET_FILE"
    FILE_NAME=$(basename "$TARGET_FILE")
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")

    # Check magic bytes for PDF (%PDF)
    if head -c 4 "$TARGET_FILE" | grep -q "%PDF"; then
        IS_PDF="true"
    fi

    # Check timestamp
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Check if Odoo is still running
APP_RUNNING="false"
if pgrep -f "odoo-bin" > /dev/null || docker ps | grep -q "odoo"; then
    APP_RUNNING="true"
fi

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_found": $FILE_FOUND,
    "file_name": "$FILE_NAME",
    "file_size": $FILE_SIZE,
    "is_pdf": $IS_PDF,
    "created_during_task": $CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="