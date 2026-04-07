#!/bin/bash
echo "=== Exporting process_patient_no_show results ==="

APPT_ID=$(cat /tmp/target_appt_id.txt 2>/dev/null || echo "0")
YESTERDAY=$(cat /tmp/target_date.txt 2>/dev/null || date -d "yesterday" +%Y-%m-%d)

echo "Checking Appointment ID: $APPT_ID"

# Query the status of the specific appointment
# NOSH stores status often as 'active', 'booked', 'arrived', 'seen', 'no_show'/'noshow'/'No Show'
STATUS_ROW=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT status, reason FROM schedule WHERE id=$APPT_ID LIMIT 1;" 2>/dev/null)

CURRENT_STATUS=$(echo "$STATUS_ROW" | awk '{print $1}')
CURRENT_REASON=$(echo "$STATUS_ROW" | cut -f2-)

echo "Final Status: $CURRENT_STATUS"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "appointment_id": "$APPT_ID",
    "target_date": "$YESTERDAY",
    "final_status": "$CURRENT_STATUS",
    "final_reason": "$CURRENT_REASON",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="