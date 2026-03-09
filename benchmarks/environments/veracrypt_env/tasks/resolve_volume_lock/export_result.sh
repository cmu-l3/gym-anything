#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Resolve Volume Lock Result ==="

REPORT_PATH="/home/ga/Documents/lock_incident.txt"
GROUND_TRUTH_PID_FILE="/tmp/.ground_truth_pid"
VOL_PATH="/home/ga/Volumes/log_storage.hc"
MOUNT_POINT="/home/ga/MountPoints/secure_logs"

# 1. Check if Volume is still mounted
# We check both VeraCrypt's list and system mounts
VC_LIST=$(veracrypt --text --list --non-interactive 2>&1 || true)
IS_MOUNTED_VC=$(echo "$VC_LIST" | grep -c "$VOL_PATH" || echo "0")
IS_MOUNTED_SYS=$(mount | grep -c "$MOUNT_POINT" || echo "0")

VOLUME_DISMOUNTED="false"
if [ "$IS_MOUNTED_VC" -eq 0 ] && [ "$IS_MOUNTED_SYS" -eq 0 ]; then
    VOLUME_DISMOUNTED="true"
fi

# 2. Check Incident Report
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -n 5) # Read first few lines
fi

# 3. Get Ground Truth PID
ACTUAL_PID=""
if [ -f "$GROUND_TRUTH_PID_FILE" ]; then
    ACTUAL_PID=$(cat "$GROUND_TRUTH_PID_FILE")
fi

# 4. Check if the locking process is still running
PROCESS_STILL_RUNNING="false"
if [ -n "$ACTUAL_PID" ] && ps -p "$ACTUAL_PID" > /dev/null; then
    PROCESS_STILL_RUNNING="true"
    # Kill it now to clean up
    kill -9 "$ACTUAL_PID" 2>/dev/null || true
fi

# 5. Anti-gaming: Check file creation time
FILE_CREATED_DURING_TASK="false"
if [ "$REPORT_EXISTS" = "true" ]; then
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 6. Capture final screenshot
take_screenshot /tmp/task_final.png

# 7. Create JSON payload
# Use python to safely escape strings for JSON
python3 -c "
import json
import os

data = {
    'volume_dismounted': $VOLUME_DISMOUNTED,
    'report_exists': $REPORT_EXISTS,
    'report_content': '''$REPORT_CONTENT''',
    'actual_pid': '$ACTUAL_PID',
    'process_still_running': $PROCESS_STILL_RUNNING,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'timestamp': '$(date -Iseconds)'
}
print(json.dumps(data))
" > /tmp/temp_result.json

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

# Cleanup
rm -f "$GROUND_TRUTH_PID_FILE"
rm -f /tmp/temp_result.json

echo "=== Export Complete ==="