#!/bin/bash
set -e
echo "=== Exporting configure_profile_graph_overlays task result ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_PATH="/home/ga/.config/Subsurface/Subsurface.conf"
CONFIG_MTIME=$(stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "0")

# Verify if config file was modified after the task started
CONFIG_MODIFIED="false"
if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
    CONFIG_MODIFIED="true"
fi

APP_RUNNING=$(pgrep -f "subsurface" > /dev/null && echo "true" || echo "false")

# Take final screenshot for VLM verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "config_mtime": $CONFIG_MTIME,
    "config_modified": $CONFIG_MODIFIED,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
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