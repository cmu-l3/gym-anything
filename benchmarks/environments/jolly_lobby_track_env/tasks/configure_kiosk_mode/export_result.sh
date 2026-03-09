#!/bin/bash
echo "=== Exporting Configure Kiosk Mode result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check for Config/Registry Changes
# Lobby Track stores settings in the Registry or AppData.
# We check if these files were modified AFTER task start.

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task start: $TASK_START"

# Check Wine Registry (user.reg)
REGISTRY_FILE="/home/ga/.wine/user.reg"
REG_MODIFIED="false"
REG_MTIME="0"

if [ -f "$REGISTRY_FILE" ]; then
    REG_MTIME=$(stat -c %Y "$REGISTRY_FILE")
    if [ "$REG_MTIME" -gt "$TASK_START" ]; then
        REG_MODIFIED="true"
        echo "Registry modified during task."
    fi
fi

# Check AppData for Jolly Technologies (XML/INI configs)
APPDATA_DIR="/home/ga/.wine/drive_c/users/ga/Application Data/Jolly Technologies"
CONFIG_MODIFIED="false"
LAST_CONFIG_FILE=""

if [ -d "$APPDATA_DIR" ]; then
    # Find any file modified after start time
    RECENT_FILE=$(find "$APPDATA_DIR" -type f -newermt "@$TASK_START" | head -n 1)
    if [ -n "$RECENT_FILE" ]; then
        CONFIG_MODIFIED="true"
        LAST_CONFIG_FILE="$RECENT_FILE"
        echo "Config file modified: $RECENT_FILE"
    fi
fi

# 3. Check if App is still running (crashes fail the task)
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Check Window Title for "Kiosk" (sometimes title changes)
WINDOW_TITLE=""
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby\|jolly\|visitor\|track" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l | grep "$WID" | cut -d' ' -f5-)
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "registry_modified": $REG_MODIFIED,
    "config_modified": $CONFIG_MODIFIED,
    "last_config_file": "$LAST_CONFIG_FILE",
    "app_running": $APP_RUNNING,
    "final_window_title": "$WINDOW_TITLE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="