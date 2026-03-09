#!/bin/bash
echo "=== Exporting cleanup_disk_space result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Retrieve target file path
TARGET_FILE=$(cat /tmp/target_file_path.txt 2>/dev/null)

if [ -z "$TARGET_FILE" ]; then
    # Fallback if setup didn't write it
    TARGET_FILE="/home/acmecorp/public_html/assets/media/temp/render_temp_vfx_full_resolution.dat"
fi

# Check if target file still exists
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    echo "Target file still exists ($FILE_SIZE bytes)"
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    echo "Target file has been removed"
fi

# Check if Firefox is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_file_path": "$TARGET_FILE",
    "target_file_exists": $FILE_EXISTS,
    "final_file_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="