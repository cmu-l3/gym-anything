#!/bin/bash
echo "=== Exporting Process Deceased Patient Results ==="

source /workspace/scripts/task_utils.sh

# Get identifiers from setup
PID=$(cat /tmp/target_pid.txt 2>/dev/null || echo "")
EID=$(cat /tmp/target_eid.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Patient Deceased Status
# We get the raw date string from the DB
DECEASED_DATE=$(librehealth_query "SELECT deceased_date FROM patient_data WHERE pid='$PID'")
echo "Deceased Date from DB: '$DECEASED_DATE'"

# 2. Query Appointment Status
# We check the status column. Common values for cancel might be 'x', 'Canceled', or a category change
# We fetch status, category, and title to be thorough
APPT_STATUS=$(librehealth_query "SELECT pc_apptstatus FROM openemr_postcalendar_events WHERE pc_eid='$EID'")
APPT_EXISTS=$(librehealth_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_eid='$EID'")

echo "Appointment Status: '$APPT_STATUS'"
echo "Appointment Exists: $APPT_EXISTS"

# 3. Capture Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "target_pid": "$PID",
    "target_eid": "$EID",
    "db_deceased_date": "$DECEASED_DATE",
    "final_appt_status": "$APPT_STATUS",
    "final_appt_exists": $APPT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved:"
cat /tmp/task_result.json
echo "=== Export Complete ==="