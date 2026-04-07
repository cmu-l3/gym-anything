#!/bin/bash
echo "=== Exporting hpv16_circular_linearization results ==="

RESULTS_DIR="/home/ga/UGENE_Data/hpv/results"
GB_PATH="${RESULTS_DIR}/hpv16_single_cutters.gb"
REPORT_PATH="${RESULTS_DIR}/linearization_report.txt"
TASK_START=$(cat /tmp/hpv16_task_start_ts 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/hpv16_task_final.png 2>/dev/null || true

# 2. Check outputs
GB_EXISTS=false
GB_SIZE=0
GB_CREATED_DURING_TASK=false

if [ -f "$GB_PATH" ]; then
    GB_EXISTS=true
    GB_SIZE=$(stat -c %s "$GB_PATH" 2>/dev/null || echo "0")
    GB_MTIME=$(stat -c %Y "$GB_PATH" 2>/dev/null || echo "0")
    if [ "$GB_MTIME" -gt "$TASK_START" ]; then
        GB_CREATED_DURING_TASK=true
    fi
fi

REPORT_EXISTS=false
REPORT_SIZE=0
REPORT_CREATED_DURING_TASK=false

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=true
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK=true
    fi
fi

APP_RUNNING=false
if pgrep -f "ugene" > /dev/null; then
    APP_RUNNING=true
fi

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "gb_exists": $GB_EXISTS,
    "gb_size_bytes": $GB_SIZE,
    "gb_created_during_task": $GB_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_size_bytes": $REPORT_SIZE,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING
}
EOF

# Move securely
rm -f /tmp/hpv_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/hpv_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/hpv_task_result.json
chmod 666 /tmp/hpv_task_result.json 2>/dev/null || sudo chmod 666 /tmp/hpv_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/hpv_task_result.json"
cat /tmp/hpv_task_result.json

echo "=== Export complete ==="