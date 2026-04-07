#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check if OpenBCI is running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Network Port Verification (Programmatic)
# Check if any process is using port 12345 (UDP)
# Note: OpenBCI GUI uses Java/Processing.
PORT_ACTIVE="false"
PORT_PROCESS=""

# Using netstat
if netstat -unlp 2>/dev/null | grep ":12345 " > /dev/null; then
    PORT_ACTIVE="true"
    PORT_PROCESS=$(netstat -unlp 2>/dev/null | grep ":12345 " | awk '{print $NF}')
fi

# Fallback using lsof if netstat failed or didn't show it
if [ "$PORT_ACTIVE" = "false" ]; then
    if lsof -i UDP:12345 2>/dev/null | grep -i "java" > /dev/null; then
        PORT_ACTIVE="true"
    fi
fi

# 4. Check for Recording File Access (Access time update)
FILE_ACCESSED="false"
RECORDING_PATH="/home/ga/Documents/OpenBCI_GUI/Recordings/OpenBCI-EEG-S001-EyesOpen.txt"
if [ -f "$RECORDING_PATH" ]; then
    # Check access time (atime)
    ATIME=$(stat -c %X "$RECORDING_PATH" 2>/dev/null || echo "0")
    if [ "$ATIME" -gt "$TASK_START" ]; then
        FILE_ACCESSED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "port_12345_active": $PORT_ACTIVE,
    "recording_file_accessed": $FILE_ACCESSED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json