#!/bin/bash
echo "=== Exporting task results ==="

# Source utilities for screenshot
source /home/ga/openbci_task_utils.sh || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
TARGET_FILE="PartialMontage.json"
FULL_PATH="${SETTINGS_DIR}/${TARGET_FILE}"

# Check output file
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$FULL_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FULL_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$FULL_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy the settings file to /tmp for easy extraction by verifier
    cp "$FULL_PATH" /tmp/task_output_settings.json
    chmod 666 /tmp/task_output_settings.json
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "settings_file_path": "/tmp/task_output_settings.json"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="