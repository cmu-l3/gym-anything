#!/bin/bash
# Export script for Mark Patient Inactive task

echo "=== Exporting Mark Patient Inactive Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# Get task timing information
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Target patient details
PATIENT_FNAME="Maria"
PATIENT_LNAME="Hickle"

# Get initial status recorded during setup
INITIAL_STATUS=$(cat /tmp/initial_patient_status.txt 2>/dev/null || echo "1")
TARGET_PID=$(cat /tmp/target_patient_pid.txt 2>/dev/null || echo "0")

# Query current patient status
echo "Querying current patient status..."
PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB, active FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null)

# Debug output
echo ""
echo "=== DEBUG: Patient query result ==="
echo "$PATIENT_DATA"
echo "=== END DEBUG ==="
echo ""

# Parse patient data
PATIENT_FOUND="false"
PATIENT_PID=""
PATIENT_ACTIVE=""
DB_FNAME=""
DB_LNAME=""
DB_DOB=""

if [ -n "$PATIENT_DATA" ]; then
    PATIENT_FOUND="true"
    PATIENT_PID=$(echo "$PATIENT_DATA" | cut -f1)
    DB_FNAME=$(echo "$PATIENT_DATA" | cut -f2)
    DB_LNAME=$(echo "$PATIENT_DATA" | cut -f3)
    DB_DOB=$(echo "$PATIENT_DATA" | cut -f4)
    PATIENT_ACTIVE=$(echo "$PATIENT_DATA" | cut -f5)
    
    echo "Patient found:"
    echo "  PID: $PATIENT_PID"
    echo "  Name: $DB_FNAME $DB_LNAME"
    echo "  DOB: $DB_DOB"
    echo "  Active Status: $PATIENT_ACTIVE"
else
    echo "Patient '$PATIENT_FNAME $PATIENT_LNAME' NOT found in database"
fi

# Check if status changed
STATUS_CHANGED="false"
if [ "$INITIAL_STATUS" = "1" ] && [ "$PATIENT_ACTIVE" = "0" ]; then
    STATUS_CHANGED="true"
    echo "Status successfully changed from Active (1) to Inactive (0)"
elif [ "$INITIAL_STATUS" = "0" ] && [ "$PATIENT_ACTIVE" = "0" ]; then
    echo "Status was already Inactive - no change detected"
elif [ "$PATIENT_ACTIVE" = "1" ]; then
    echo "Status is still Active (1) - task not completed"
fi

# Verify correct patient was modified (anti-gaming)
CORRECT_PATIENT="false"
if [ "$PATIENT_PID" = "$TARGET_PID" ] && [ -n "$TARGET_PID" ] && [ "$TARGET_PID" != "0" ]; then
    CORRECT_PATIENT="true"
    echo "Correct patient was modified (PID: $TARGET_PID)"
fi

# Check for any recently modified patient records (detect if wrong patient was changed)
echo ""
echo "Checking for any recently modified inactive patients..."
RECENT_INACTIVE=$(openemr_query "SELECT pid, fname, lname, active FROM patient_data WHERE active=0 ORDER BY pid DESC LIMIT 5" 2>/dev/null)
echo "Recently inactive patients:"
echo "$RECENT_INACTIVE"

# Escape special characters for JSON
DB_FNAME_ESCAPED=$(echo "$DB_FNAME" | sed 's/"/\\"/g')
DB_LNAME_ESCAPED=$(echo "$DB_LNAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/inactive_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "target_patient": {
        "fname": "$PATIENT_FNAME",
        "lname": "$PATIENT_LNAME",
        "expected_pid": "$TARGET_PID"
    },
    "patient_found": $PATIENT_FOUND,
    "patient_data": {
        "pid": "$PATIENT_PID",
        "fname": "$DB_FNAME_ESCAPED",
        "lname": "$DB_LNAME_ESCAPED",
        "dob": "$DB_DOB",
        "active": "$PATIENT_ACTIVE"
    },
    "verification": {
        "initial_status": "$INITIAL_STATUS",
        "current_status": "$PATIENT_ACTIVE",
        "status_changed": $STATUS_CHANGED,
        "correct_patient_modified": $CORRECT_PATIENT
    },
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/mark_inactive_result.json 2>/dev/null || sudo rm -f /tmp/mark_inactive_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/mark_inactive_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/mark_inactive_result.json
chmod 666 /tmp/mark_inactive_result.json 2>/dev/null || sudo chmod 666 /tmp/mark_inactive_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/mark_inactive_result.json"
cat /tmp/mark_inactive_result.json

echo ""
echo "=== Export Complete ==="