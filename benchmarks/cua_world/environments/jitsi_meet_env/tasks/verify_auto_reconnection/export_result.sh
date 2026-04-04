#!/bin/bash
set -e

echo "=== Exporting verify_auto_reconnection result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RECONNECTING_IMG="/home/ga/reconnecting_state.png"
RESTORED_IMG="/home/ga/restored_state.png"

# 1. Check Evidence File 1: Reconnecting State
REC_EXISTS="false"
REC_VALID_TIME="false"
if [ -f "$RECONNECTING_IMG" ]; then
    REC_EXISTS="true"
    REC_MTIME=$(stat -c %Y "$RECONNECTING_IMG")
    if [ "$REC_MTIME" -gt "$TASK_START" ]; then
        REC_VALID_TIME="true"
    fi
fi

# 2. Check Evidence File 2: Restored State
RES_EXISTS="false"
RES_VALID_TIME="false"
if [ -f "$RESTORED_IMG" ]; then
    RES_EXISTS="true"
    RES_MTIME=$(stat -c %Y "$RESTORED_IMG")
    if [ "$RES_MTIME" -gt "$TASK_START" ]; then
        RES_VALID_TIME="true"
    fi
fi

# 3. Check Service Status (JVB should be running at the end)
cd /home/ga/jitsi
# 'docker compose ps' output format varies, check if Up
if docker compose ps jvb | grep -i "Up" > /dev/null; then
    JVB_RUNNING="true"
else
    JVB_RUNNING="false"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Export JSON
cat > /tmp/task_result.json << EOF
{
    "reconnecting_exists": $REC_EXISTS,
    "reconnecting_created_during_task": $REC_VALID_TIME,
    "restored_exists": $RES_EXISTS,
    "restored_created_during_task": $RES_VALID_TIME,
    "jvb_running_at_end": $JVB_RUNNING,
    "reconnecting_path": "$RECONNECTING_IMG",
    "restored_path": "$RESTORED_IMG"
}
EOF

# Ensure accessible
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json