#!/bin/bash
# Export script for Register New Patient task

echo "=== Exporting Register New Patient Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png
echo "Final screenshot saved"

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get patient counts
INITIAL_COUNT=$(cat /tmp/initial_patient_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM patient_data" 2>/dev/null || echo "0")

echo "Patient count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Expected patient details
EXPECTED_FNAME="Marcus"
EXPECTED_LNAME="Wellington"

# Debug: Show most recent patients
echo ""
echo "=== DEBUG: Most recent patients in database ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT pid, fname, lname, DOB, sex, street, city, state, postal_code, phone_cell, email, date 
     FROM patient_data ORDER BY pid DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Query for the expected patient (case-insensitive)
echo "Searching for patient '$EXPECTED_FNAME $EXPECTED_LNAME'..."
PATIENT_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pid, fname, lname, DOB, sex, street, city, state, postal_code, phone_cell, email, UNIX_TIMESTAMP(date) as created_ts 
     FROM patient_data 
     WHERE LOWER(TRIM(fname))=LOWER('$EXPECTED_FNAME') AND LOWER(TRIM(lname))=LOWER('$EXPECTED_LNAME')
     ORDER BY pid DESC LIMIT 1" 2>/dev/null)

# Parse patient data
PATIENT_FOUND="false"
PATIENT_PID=""
PATIENT_FNAME=""
PATIENT_LNAME=""
PATIENT_DOB=""
PATIENT_SEX=""
PATIENT_STREET=""
PATIENT_CITY=""
PATIENT_STATE=""
PATIENT_POSTAL=""
PATIENT_PHONE=""
PATIENT_EMAIL=""
PATIENT_CREATED_TS="0"

if [ -n "$PATIENT_DATA" ]; then
    PATIENT_FOUND="true"
    PATIENT_PID=$(echo "$PATIENT_DATA" | cut -f1)
    PATIENT_FNAME=$(echo "$PATIENT_DATA" | cut -f2)
    PATIENT_LNAME=$(echo "$PATIENT_DATA" | cut -f3)
    PATIENT_DOB=$(echo "$PATIENT_DATA" | cut -f4)
    PATIENT_SEX=$(echo "$PATIENT_DATA" | cut -f5)
    PATIENT_STREET=$(echo "$PATIENT_DATA" | cut -f6)
    PATIENT_CITY=$(echo "$PATIENT_DATA" | cut -f7)
    PATIENT_STATE=$(echo "$PATIENT_DATA" | cut -f8)
    PATIENT_POSTAL=$(echo "$PATIENT_DATA" | cut -f9)
    PATIENT_PHONE=$(echo "$PATIENT_DATA" | cut -f10)
    PATIENT_EMAIL=$(echo "$PATIENT_DATA" | cut -f11)
    PATIENT_CREATED_TS=$(echo "$PATIENT_DATA" | cut -f12)
    
    echo "Patient found:"
    echo "  PID: $PATIENT_PID"
    echo "  Name: $PATIENT_FNAME $PATIENT_LNAME"
    echo "  DOB: $PATIENT_DOB"
    echo "  Sex: $PATIENT_SEX"
    echo "  Address: $PATIENT_STREET, $PATIENT_CITY, $PATIENT_STATE $PATIENT_POSTAL"
    echo "  Phone: $PATIENT_PHONE"
    echo "  Email: $PATIENT_EMAIL"
    echo "  Created timestamp: $PATIENT_CREATED_TS"
else
    echo "Patient '$EXPECTED_FNAME $EXPECTED_LNAME' NOT found in database"
    
    # Check if any new patients were added
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
        echo "Note: New patient(s) were added but not with expected name"
        NEWEST=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
            "SELECT fname, lname FROM patient_data ORDER BY pid DESC LIMIT 1" 2>/dev/null)
        echo "Most recent patient: $NEWEST"
    fi
fi

# Check if patient was created during task window
CREATED_DURING_TASK="false"
if [ "$PATIENT_CREATED_TS" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
    echo "Patient was created during task execution"
else
    echo "Patient creation timestamp ($PATIENT_CREATED_TS) is not after task start ($TASK_START)"
fi

# Normalize phone number for comparison (remove non-digits)
PATIENT_PHONE_NORMALIZED=$(echo "$PATIENT_PHONE" | tr -cd '0-9')

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}

PATIENT_FNAME_ESC=$(escape_json "$PATIENT_FNAME")
PATIENT_LNAME_ESC=$(escape_json "$PATIENT_LNAME")
PATIENT_STREET_ESC=$(escape_json "$PATIENT_STREET")
PATIENT_CITY_ESC=$(escape_json "$PATIENT_CITY")
PATIENT_STATE_ESC=$(escape_json "$PATIENT_STATE")
PATIENT_EMAIL_ESC=$(escape_json "$PATIENT_EMAIL")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/register_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_patient_count": ${INITIAL_COUNT:-0},
    "current_patient_count": ${CURRENT_COUNT:-0},
    "patient_found": $PATIENT_FOUND,
    "created_during_task": $CREATED_DURING_TASK,
    "patient": {
        "pid": "$PATIENT_PID",
        "fname": "$PATIENT_FNAME_ESC",
        "lname": "$PATIENT_LNAME_ESC",
        "dob": "$PATIENT_DOB",
        "sex": "$PATIENT_SEX",
        "street": "$PATIENT_STREET_ESC",
        "city": "$PATIENT_CITY_ESC",
        "state": "$PATIENT_STATE_ESC",
        "postal_code": "$PATIENT_POSTAL",
        "phone_cell": "$PATIENT_PHONE",
        "phone_normalized": "$PATIENT_PHONE_NORMALIZED",
        "email": "$PATIENT_EMAIL_ESC",
        "created_timestamp": $PATIENT_CREATED_TS
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/register_new_patient_result.json 2>/dev/null || sudo rm -f /tmp/register_new_patient_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/register_new_patient_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/register_new_patient_result.json
chmod 666 /tmp/register_new_patient_result.json 2>/dev/null || sudo chmod 666 /tmp/register_new_patient_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/register_new_patient_result.json"
cat /tmp/register_new_patient_result.json

echo ""
echo "=== Export Complete ==="