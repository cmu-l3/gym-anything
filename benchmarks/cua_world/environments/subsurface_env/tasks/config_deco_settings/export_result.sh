#!/bin/bash
set -e
echo "=== Exporting config_deco_settings task result ==="

export DISPLAY="${DISPLAY:-:1}"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

CONF_FILE="/home/ga/.config/Subsurface/Subsurface.conf"
CONF_EXISTS="false"
CONF_MTIME="0"
CONF_SIZE="0"

if [ -f "$CONF_FILE" ]; then
    CONF_EXISTS="true"
    CONF_MTIME=$(stat -c %Y "$CONF_FILE" 2>/dev/null || echo "0")
    CONF_SIZE=$(stat -c %s "$CONF_FILE" 2>/dev/null || echo "0")
fi

APP_RUNNING="false"
if pgrep -f "subsurface" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": $CONF_EXISTS,
    "config_mtime": $CONF_MTIME,
    "config_size": $CONF_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_exists": true
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="