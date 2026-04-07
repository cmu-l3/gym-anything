#!/bin/bash
set -e
echo "=== Exporting task results ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONF_FILE="/home/ga/.config/Subsurface/Subsurface.conf"

# 1. Take final screenshot BEFORE gracefully closing the app
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check if application was running
APP_RUNNING=$(pgrep -f "subsurface" > /dev/null && echo "true" || echo "false")

# 3. Gracefully close Subsurface to ensure QSettings flushes preferences to disk
if [ "$APP_RUNNING" = "true" ]; then
    DISPLAY=:1 wmctrl -c "Subsurface" 2>/dev/null || true
    sleep 3
    # If a save prompt interrupted the close, cancel it so config still writes 
    if pgrep -f "subsurface" > /dev/null; then
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 1
        pkill -f subsurface 2>/dev/null || true
    fi
fi

# 4. Gather config file statistics
if [ -f "$CONF_FILE" ]; then
    CONF_MTIME=$(stat -c %Y "$CONF_FILE" 2>/dev/null || echo "0")
    CONF_EXISTS="true"
else
    CONF_MTIME="0"
    CONF_EXISTS="false"
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": $CONF_EXISTS,
    "config_mtime": $CONF_MTIME,
    "app_was_running": $APP_RUNNING
}
EOF

# Safely copy to destination
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="