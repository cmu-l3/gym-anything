#!/bin/bash
echo "=== Exporting Configure Time-Frequency Playback Layout results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if OpenBCI GUI is running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 2. Check if the playback file exists (sanity check)
FILE_EXISTS="false"
if [ -f "/home/ga/Documents/OpenBCI_GUI/Recordings/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    FILE_EXISTS="true"
fi

# 3. Capture final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "playback_file_exists": $FILE_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="