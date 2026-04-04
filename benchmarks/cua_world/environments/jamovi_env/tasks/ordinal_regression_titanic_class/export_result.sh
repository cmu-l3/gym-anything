#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check OMV file
OMV_PATH="/home/ga/Documents/Jamovi/Titanic_Ordinal.omv"
OMV_EXISTS="false"
OMV_CREATED="false"
OMV_SIZE=0

if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH")
    OMV_MTIME=$(stat -c %Y "$OMV_PATH")
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED="true"
    fi
fi

# 3. Check Report file
TXT_PATH="/home/ga/Documents/Jamovi/ordinal_results.txt"
TXT_EXISTS="false"
TXT_CREATED="false"

if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
    TXT_MTIME=$(stat -c %Y "$TXT_PATH")
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_CREATED="true"
    fi
fi

# 4. App State
APP_RUNNING="false"
if pgrep -f "org.jamovi.jamovi" >/dev/null || pgrep -f "jamovi" >/dev/null; then
    APP_RUNNING="true"
fi

# 5. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. JSON Payload
# We will inspect the OMV content in the python verifier, so we just report file stats here.
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED,
    "omv_size_bytes": $OMV_SIZE,
    "report_exists": $TXT_EXISTS,
    "report_created_during_task": $TXT_CREATED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json