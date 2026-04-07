#!/bin/bash
echo "=== Exporting add_patient_insurance result ==="

DB_EXEC="docker exec -i nosh-db mysql -uroot -prootpassword nosh"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_PID=$(cat /tmp/task_patient_pid.txt 2>/dev/null || echo "")
INITIAL_COUNT=$(cat /tmp/initial_insurance_count.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ -z "$PATIENT_PID" ]; then
    echo "ERROR: Patient PID not found"
    PATIENT_PID="0"
fi

# Get current insurance count
CURRENT_COUNT=$(echo "SELECT COUNT(*) FROM insurance WHERE pid = $PATIENT_PID;" | $DB_EXEC -N 2>/dev/null | tr -d '[:space:]')

# Fetch the most recently added insurance record for this patient
# We select based on MAX(insurance_id) for this patient
INS_DATA=$(echo "SELECT insurance_plan_name, insurance_id_num, insurance_group, insurance_order, copay, insurance_insu_lastname, insurance_insu_firstname, insurance_relationship FROM insurance WHERE pid = $PATIENT_PID ORDER BY insurance_id DESC LIMIT 1;" | $DB_EXEC -N 2>/dev/null)

# Check if record exists
RECORD_EXISTS="false"
if [ -n "$INS_DATA" ]; then
    RECORD_EXISTS="true"
fi

# Parse fields (tab-separated by default in mysql -N output)
# Note: Empty fields might shift columns if not careful, but mysql -N outputs tabs.
# We'll use python to parse safely if needed, or awk.
INS_PLAN=$(echo "$INS_DATA" | awk -F'\t' '{print $1}')
INS_ID=$(echo "$INS_DATA" | awk -F'\t' '{print $2}')
INS_GROUP=$(echo "$INS_DATA" | awk -F'\t' '{print $3}')
INS_ORDER=$(echo "$INS_DATA" | awk -F'\t' '{print $4}')
INS_COPAY=$(echo "$INS_DATA" | awk -F'\t' '{print $5}')
INS_LNAME=$(echo "$INS_DATA" | awk -F'\t' '{print $6}')
INS_FNAME=$(echo "$INS_DATA" | awk -F'\t' '{print $7}')
INS_RELATION=$(echo "$INS_DATA" | awk -F'\t' '{print $8}')

# Escape for JSON
INS_PLAN_ESC=$(echo "$INS_PLAN" | sed 's/"/\\"/g')
INS_GROUP_ESC=$(echo "$INS_GROUP" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "current_count": ${CURRENT_COUNT:-0},
    "record_exists": $RECORD_EXISTS,
    "patient_pid": "$PATIENT_PID",
    "insurance_data": {
        "plan_name": "$INS_PLAN_ESC",
        "id_number": "$INS_ID",
        "group_number": "$INS_GROUP_ESC",
        "order": "$INS_ORDER",
        "copay": "$INS_COPAY",
        "subscriber_firstname": "$INS_FNAME",
        "subscriber_lastname": "$INS_LNAME",
        "relationship": "$INS_RELATION"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="