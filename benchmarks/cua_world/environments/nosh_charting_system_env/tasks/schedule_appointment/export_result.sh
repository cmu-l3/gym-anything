#!/bin/bash
echo "=== Exporting Schedule Appointment Results ==="

# 1. Capture Final State
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Read Context Data (from setup)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_PID=$(cat /tmp/expected_pid.txt 2>/dev/null || echo "")
EXPECTED_DATETIME=$(cat /tmp/expected_datetime.txt 2>/dev/null || echo "")
EXPECTED_VISITTYPE=$(cat /tmp/expected_visittype.txt 2>/dev/null || echo "")
INITIAL_COUNT=$(cat /tmp/initial_schedule_count.txt 2>/dev/null || echo "0")

# 3. Query Current Database State
# We look for appointments created AFTER the task started
# We fetch specific fields: id, pid, provider_id, start_time, type, reasons
# Provider ID for Dr. Carter is usually 2 based on setup scripts, but we check logic in verifier.
# Using 'schedule' table.

LATEST_APPT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "
    SELECT 
        id, 
        pid, 
        provider_id, 
        start, 
        end, 
        type
    FROM schedule 
    WHERE pid='$EXPECTED_PID' 
    ORDER BY id DESC LIMIT 1
" 2>/dev/null)

CURRENT_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM schedule")

# Parse result
if [ -n "$LATEST_APPT" ]; then
    APPT_FOUND="true"
    ACTUAL_ID=$(echo "$LATEST_APPT" | cut -f1)
    ACTUAL_PID=$(echo "$LATEST_APPT" | cut -f2)
    ACTUAL_PROV_ID=$(echo "$LATEST_APPT" | cut -f3)
    ACTUAL_START=$(echo "$LATEST_APPT" | cut -f4) # Format: YYYY-MM-DD HH:MM:SS
    ACTUAL_TYPE=$(echo "$LATEST_APPT" | cut -f6)
else
    APPT_FOUND="false"
    ACTUAL_ID=""
    ACTUAL_PID=""
    ACTUAL_PROV_ID=""
    ACTUAL_START=""
    ACTUAL_TYPE=""
fi

# Check if count increased (Anti-gaming: did they actually add something?)
COUNT_INCREASED="false"
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    COUNT_INCREASED="true"
fi

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "count_increased": $COUNT_INCREASED,
    "appointment_found": $APPT_FOUND,
    "actual": {
        "id": "$ACTUAL_ID",
        "pid": "$ACTUAL_PID",
        "provider_id": "$ACTUAL_PROV_ID",
        "start_datetime": "$ACTUAL_START",
        "visit_type": "$ACTUAL_TYPE"
    },
    "expected": {
        "pid": "$EXPECTED_PID",
        "datetime": "$EXPECTED_DATETIME",
        "visit_type": "$EXPECTED_VISITTYPE",
        "provider_id_target": "2" 
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="