#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Capture Final State
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OMV_PATH="/home/ga/Documents/Jamovi/Extraversion_Scale.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/scale_report.txt"

OMV_EXISTS="false"
OMV_CREATED="false"
if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_MTIME=$(stat -c %Y "$OMV_PATH")
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED="true"
    fi
fi

REPORT_EXISTS="false"
REPORT_CREATED="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED="true"
    fi
fi

# 3. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED,
    "omv_path": "$OMV_PATH",
    "report_path": "$REPORT_PATH",
    "data_path": "/home/ga/Documents/Jamovi/BFI25.csv"
}
EOF

# 4. Permissions (allow verify to read)
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final.png 2>/dev/null || true
if [ -f "$OMV_PATH" ]; then chmod 644 "$OMV_PATH"; fi
if [ -f "$REPORT_PATH" ]; then chmod 644 "$REPORT_PATH"; fi

echo "=== Export Complete ==="
cat /tmp/task_result.json