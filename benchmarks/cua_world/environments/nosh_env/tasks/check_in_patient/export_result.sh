#!/bin/bash
echo "=== Exporting Check In Patient Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
APPT_ID=$(cat /tmp/target_appt_id.txt 2>/dev/null || echo "0")

echo "Checking Appointment ID: $APPT_ID"

# 1. Query Database for Final State of the Appointment
# We retrieve: status, reason, and updated_date
DB_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT status, reason, UNIX_TIMESTAMP(updated_date) FROM schedule WHERE id=${APPT_ID};" 2>/dev/null)

# Parse DB Result (Tab separated)
FINAL_STATUS=$(echo "$DB_RESULT" | awk '{print $1}')
# Reason might contain spaces, so we cut from 2nd field to second to last (before timestamp)? 
# Actually simpler to query fields individually to avoid parsing issues with spaces
FINAL_STATUS=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT status FROM schedule WHERE id=${APPT_ID};" 2>/dev/null)
FINAL_REASON=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT reason FROM schedule WHERE id=${APPT_ID};" 2>/dev/null)
UPDATED_TS=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT UNIX_TIMESTAMP(updated_date) FROM schedule WHERE id=${APPT_ID};" 2>/dev/null)

# Escape reason for JSON
SAFE_REASON=$(echo "$FINAL_REASON" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/ /g')

# 2. Check if App was running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "appt_id": "$APPT_ID",
    "final_status": "$FINAL_STATUS",
    "final_reason": "$SAFE_REASON",
    "db_updated_ts": ${UPDATED_TS:-0},
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="