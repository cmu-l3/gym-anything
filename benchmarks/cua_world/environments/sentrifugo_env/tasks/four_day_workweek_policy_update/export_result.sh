#!/bin/bash
echo "=== Exporting four_day_workweek_policy_update result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Leave Types
AL_DAYS=$(sentrifugo_db_query "SELECT numberofdays FROM main_employeeleavetypes WHERE leavetype='Annual Leave' AND isactive=1 LIMIT 1;" 2>/dev/null | tr -d '[:space:]' | cut -d'.' -f1)
SL_DAYS=$(sentrifugo_db_query "SELECT numberofdays FROM main_employeeleavetypes WHERE leavetype='Sick Leave' AND isactive=1 LIMIT 1;" 2>/dev/null | tr -d '[:space:]' | cut -d'.' -f1)

WD_DATA=$(sentrifugo_db_query "SELECT leavecode, numberofdays FROM main_employeeleavetypes WHERE leavetype='Wellness Day' AND isactive=1 LIMIT 1;" 2>/dev/null)
WD_CODE=""
WD_DAYS=""
if [ -n "$WD_DATA" ]; then
    WD_CODE=$(echo "$WD_DATA" | cut -f1 | tr -d '[:space:]')
    WD_DAYS=$(echo "$WD_DATA" | cut -f2 | tr -d '[:space:]' | cut -d'.' -f1)
fi

# Query Shift "General Shift"
SHIFT_START=""
SHIFT_END=""
for table in main_shifts main_workingshifts main_workshifts; do
    SHIFT_DATA=$(sentrifugo_db_query "SELECT starttime, endtime FROM $table WHERE shiftname='General Shift' AND isactive=1 LIMIT 1;" 2>/dev/null)
    if [ -n "$SHIFT_DATA" ]; then
        SHIFT_START=$(echo "$SHIFT_DATA" | cut -f1 | tr -d '[:space:]')
        SHIFT_END=$(echo "$SHIFT_DATA" | cut -f2 | tr -d '[:space:]')
        break
    fi
done

APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "annual_leave_days": "$AL_DAYS",
    "sick_leave_days": "$SL_DAYS",
    "wellness_day_code": "$WD_CODE",
    "wellness_day_days": "$WD_DAYS",
    "shift_start": "$SHIFT_START",
    "shift_end": "$SHIFT_END",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="