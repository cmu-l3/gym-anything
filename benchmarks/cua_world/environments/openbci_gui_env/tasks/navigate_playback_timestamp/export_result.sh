#!/bin/bash
set -e
echo "=== Exporting navigate_playback_timestamp results ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh || true

# 1. Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check if OpenBCI is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Take final screenshot (CRITICAL for VLM verification)
take_screenshot /tmp/task_final.png

# 4. Create result JSON
# We don't have programmatic access to the internal playback time, 
# so we rely entirely on the screenshot for the success criteria.
# We just export metadata here.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "recordings_dir_contents": "$(ls /home/ga/Documents/OpenBCI_GUI/Recordings/ | tr '\n' ',')"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="