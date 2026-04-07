#!/bin/bash
echo "=== Exporting CanSat Payload Expansion Retrofit Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

ORK_PATH="/home/ga/Documents/rockets/cansat_retrofit.ork"
REPORT_PATH="/home/ga/Documents/exports/cansat_report.txt"

# Check output ORK file
ORK_EXISTS="false"
ORK_CREATED_DURING_TASK="false"
ORK_SIZE="0"
if [ -f "$ORK_PATH" ]; then
    ORK_EXISTS="true"
    ORK_MTIME=$(stat -c %Y "$ORK_PATH" 2>/dev/null || echo "0")
    if [ "$ORK_MTIME" -gt "$TASK_START" ]; then
        ORK_CREATED_DURING_TASK="true"
    fi
    ORK_SIZE=$(stat -c %s "$ORK_PATH" 2>/dev/null || echo "0")
fi

# Check output Report file
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE="0"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/cansat_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ork_exists": $ORK_EXISTS,
    "ork_created_during_task": $ORK_CREATED_DURING_TASK,
    "ork_size": $ORK_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size": $REPORT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/cansat_result.json 2>/dev/null || sudo rm -f /tmp/cansat_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/cansat_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/cansat_result.json
chmod 666 /tmp/cansat_result.json 2>/dev/null || sudo chmod 666 /tmp/cansat_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/cansat_result.json"
cat /tmp/cansat_result.json
echo "=== Export complete ==="