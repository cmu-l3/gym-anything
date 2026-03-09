#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Result ==="

MOUNT_POINT="/home/ga/MountPoints/HR_Archive"
REPORT_PATH="/home/ga/Documents/lock_incident_report.txt"

# 1. Check if Volume is Dismounted
IS_DISMOUNTED="false"
if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    IS_DISMOUNTED="true"
fi

# Double check with VeraCrypt CLI
VC_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
if echo "$VC_LIST" | grep -q "$MOUNT_POINT"; then
    IS_DISMOUNTED="false"
fi

# 2. Check if blocking processes are still running
# Load original PIDs
BLOCKED_PIDS_RUNNING="false"
if [ -f /tmp/blocking_pids.txt ]; then
    while read pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "Process $pid is still running"
            BLOCKED_PIDS_RUNNING="true"
        fi
    done < /tmp/blocking_pids.txt
fi

# 3. Check Report
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Limit size
fi

# 4. Anti-gaming: Check report timestamp
REPORT_VALID_TIME="false"
if [ "$REPORT_EXISTS" = "true" ]; then
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_VALID_TIME="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
# Escape content for JSON
REPORT_CONTENT_SAFE=$(echo "$REPORT_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' | sed 's/^"//;s/"$//')

RESULT_JSON=$(cat << EOF
{
    "volume_dismounted": $IS_DISMOUNTED,
    "blocking_processes_running": $BLOCKED_PIDS_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_VALID_TIME,
    "report_content": "$REPORT_CONTENT_SAFE",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

# Cleanup (Force kill any remaining processes to leave clean state)
if [ -f /tmp/blocking_pids.txt ]; then
    while read pid; do
        kill -9 "$pid" 2>/dev/null || true
    done < /tmp/blocking_pids.txt
fi

echo "Result saved."
cat /tmp/task_result.json
echo "=== Export Complete ==="