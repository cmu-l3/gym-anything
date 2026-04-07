#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONF_FILE="/home/ga/.config/Subsurface/Subsurface.conf"

CONF_EXISTS="false"
CONF_MTIME="0"
CONF_MODIFIED="false"

# Check if Subsurface's Qt configuration file has been written to disk
if [ -f "$CONF_FILE" ]; then
    CONF_EXISTS="true"
    CONF_MTIME=$(stat -c%Y "$CONF_FILE" 2>/dev/null || echo "0")
    if [ "$CONF_MTIME" -gt "$TASK_START" ]; then
        CONF_MODIFIED="true"
    fi
fi

# Determine if the application is still running 
# (Subsurface often only writes configuration files cleanly on exit)
APP_RUNNING=$(pgrep -f "subsurface" > /dev/null && echo "true" || echo "false")

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Save result payload using a temp file to guarantee permission stability
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "conf_exists": $CONF_EXISTS,
    "conf_mtime": $CONF_MTIME,
    "conf_modified_during_task": $CONF_MODIFIED,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="