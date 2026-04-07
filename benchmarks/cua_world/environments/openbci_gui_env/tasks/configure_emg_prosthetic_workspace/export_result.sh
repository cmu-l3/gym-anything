#!/bin/bash
echo "=== Exporting EMG Workspace Configuration Results ==="

# Source utilities
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
else
    function take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# 1. Capture Final Desktop Screenshot (for VLM verification of GUI state)
take_screenshot /tmp/task_final.png

# 2. Gather Task Metadata
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)
TARGET_FILE="/home/ga/Documents/OpenBCI_GUI/Screenshots/emg_workspace.png"

# 3. Check specific file requirement (The agent was asked to save a screenshot)
FILE_EXISTS=false
FILE_SIZE=0
FILE_CREATED_DURING_TASK=false

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c%s "$TARGET_FILE")
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
fi

# 4. Check if App is running
APP_RUNNING=false
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING=true
fi

# 5. Create Result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start_time": $TASK_START_TIME,
    "export_time": $CURRENT_TIME,
    "app_running": $APP_RUNNING,
    "target_file_exists": $FILE_EXISTS,
    "target_file_size": $FILE_SIZE,
    "target_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "target_file_path": "$TARGET_FILE"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json