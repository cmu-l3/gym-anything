#!/bin/bash
echo "=== Exporting earthquake_data_analysis task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/earthquake_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/earthquake_task_start_ts 2>/dev/null || echo "0")
SCRIPT_PATH="/home/ga/Documents/earthquake_analysis.py"
REPORT_PATH="/home/ga/Documents/earthquake_report.txt"

SCRIPT_EXISTS="false"
SCRIPT_SIZE=0
SCRIPT_MODIFIED="false"

REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MODIFIED="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat --format=%s "$SCRIPT_PATH" 2>/dev/null || echo "0")
    SCRIPT_MTIME=$(stat --format=%Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat --format=%s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat --format=%Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
fi

cat > /tmp/earthquake_task_result.json << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "script_size": $SCRIPT_SIZE,
    "script_modified": $SCRIPT_MODIFIED,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_modified": $REPORT_MODIFIED
}
EOF

chmod 666 /tmp/earthquake_task_result.json

# Copy files to /tmp for easy retrieval by verifier
if [ "$SCRIPT_EXISTS" = "true" ]; then
    cp "$SCRIPT_PATH" /tmp/agent_script.py 2>/dev/null || true
    chmod 666 /tmp/agent_script.py 2>/dev/null || true
fi

if [ "$REPORT_EXISTS" = "true" ]; then
    cp "$REPORT_PATH" /tmp/agent_report.txt 2>/dev/null || true
    chmod 666 /tmp/agent_report.txt 2>/dev/null || true
fi

echo "Result saved to /tmp/earthquake_task_result.json"
cat /tmp/earthquake_task_result.json
echo "=== Export complete ==="