#!/bin/bash
echo "=== Exporting Interface LOS Simulation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Stop the monitor
if [ -f /var/lib/app/ground_truth/monitor.pid ]; then
    kill $(cat /var/lib/app/ground_truth/monitor.pid) 2>/dev/null || true
    pkill -f "monitor.sh" 2>/dev/null || true
fi

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
AGENT_FILE="/home/ga/Desktop/los_event_report.json"

FILE_EXISTS=false
FILE_IS_NEW=false

if [ -f "$AGENT_FILE" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$AGENT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi
fi

# Take final screenshot
DISPLAY=:1 import -window root /tmp/los_simulation_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/los_simulation_end.png 2>/dev/null || true

# Safely encode log to JSON string
if [ -f "/var/lib/app/ground_truth/iface_history.log" ]; then
    GT_LOG_JSON=$(jq -Rs . < /var/lib/app/ground_truth/iface_history.log)
else
    GT_LOG_JSON='""'
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "gt_log": $GT_LOG_JSON
}
EOF

rm -f /tmp/los_simulation_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/los_simulation_result.json
chmod 666 /tmp/los_simulation_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export Complete. Log generated."