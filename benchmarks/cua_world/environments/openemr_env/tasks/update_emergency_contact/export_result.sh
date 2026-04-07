#!/bin/bash
# Export script for Update Emergency Contact Task

echo "=== Exporting Update Emergency Contact Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot first
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# Target patient
PATIENT_PID=2

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_MODIFIED=$(cat /tmp/initial_patient_modified.txt 2>/dev/null || echo "0")

# Get initial values for comparison
INITIAL_EM_CONTACT=$(cat /tmp/initial_em_contact.txt 2>/dev/null || echo "")
INITIAL_EM_PHONE=$(cat /tmp/initial_em_phone.txt 2>/dev/null || echo "")

echo "Task timing: start=$TASK_START, end=$TASK_END"
echo "Initial values: contact='$INITIAL_EM_CONTACT', phone='$INITIAL_EM_PHONE'"

# Query current emergency contact values
echo ""
echo "=== Querying current emergency contact for patient PID=$PATIENT_PID ==="
CURRENT_DATA=$(openemr_query "SELECT pid, fname, lname, em_contact, em_phone, UNIX_TIMESTAMP(date) as modified_ts FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Current patient data: $CURRENT_DATA"

# Parse the data
CURRENT_PID=$(echo "$CURRENT_DATA" | cut -f1)
CURRENT_FNAME=$(echo "$CURRENT_DATA" | cut -f2)
CURRENT_LNAME=$(echo "$CURRENT_DATA" | cut -f3)
CURRENT_EM_CONTACT=$(echo "$CURRENT_DATA" | cut -f4)
CURRENT_EM_PHONE=$(echo "$CURRENT_DATA" | cut -f5)
CURRENT_MODIFIED=$(echo "$CURRENT_DATA" | cut -f6)

echo ""
echo "Parsed values:"
echo "  Patient: $CURRENT_FNAME $CURRENT_LNAME (pid=$CURRENT_PID)"
echo "  Emergency Contact: '$CURRENT_EM_CONTACT'"
echo "  Emergency Phone: '$CURRENT_EM_PHONE'"
echo "  Last Modified Timestamp: $CURRENT_MODIFIED"

# Check if values changed
CONTACT_CHANGED="false"
PHONE_CHANGED="false"
RECORD_MODIFIED="false"

if [ "$CURRENT_EM_CONTACT" != "$INITIAL_EM_CONTACT" ]; then
    CONTACT_CHANGED="true"
    echo "Emergency contact name CHANGED: '$INITIAL_EM_CONTACT' -> '$CURRENT_EM_CONTACT'"
else
    echo "Emergency contact name unchanged"
fi

if [ "$CURRENT_EM_PHONE" != "$INITIAL_EM_PHONE" ]; then
    PHONE_CHANGED="true"
    echo "Emergency phone CHANGED: '$INITIAL_EM_PHONE' -> '$CURRENT_EM_PHONE'"
else
    echo "Emergency phone unchanged"
fi

# Check if record was modified after task start
if [ -n "$CURRENT_MODIFIED" ] && [ "$CURRENT_MODIFIED" != "NULL" ]; then
    if [ "$CURRENT_MODIFIED" -gt "$TASK_START" ]; then
        RECORD_MODIFIED="true"
        echo "Record was modified during task (timestamp: $CURRENT_MODIFIED > $TASK_START)"
    else
        echo "Record modification timestamp not updated during task"
    fi
fi

# Normalize phone number for comparison (extract digits only)
CURRENT_EM_PHONE_DIGITS=$(echo "$CURRENT_EM_PHONE" | tr -dc '0-9')
echo "Phone digits only: $CURRENT_EM_PHONE_DIGITS"

# Check if expected values are present
EXPECTED_CONTACT="Robert Will"
EXPECTED_PHONE_DIGITS="6175559876"

CONTACT_CORRECT="false"
PHONE_CORRECT="false"

# Case-insensitive comparison for contact name
CURRENT_EM_CONTACT_LOWER=$(echo "$CURRENT_EM_CONTACT" | tr '[:upper:]' '[:lower:]')
EXPECTED_CONTACT_LOWER=$(echo "$EXPECTED_CONTACT" | tr '[:upper:]' '[:lower:]')

if [ "$CURRENT_EM_CONTACT_LOWER" = "$EXPECTED_CONTACT_LOWER" ]; then
    CONTACT_CORRECT="true"
    echo "Contact name matches expected value"
elif echo "$CURRENT_EM_CONTACT_LOWER" | grep -q "robert.*will\|will.*robert"; then
    CONTACT_CORRECT="true"
    echo "Contact name contains expected name (partial match)"
fi

if [ "$CURRENT_EM_PHONE_DIGITS" = "$EXPECTED_PHONE_DIGITS" ]; then
    PHONE_CORRECT="true"
    echo "Phone number matches expected value"
elif echo "$CURRENT_EM_PHONE_DIGITS" | grep -q "$EXPECTED_PHONE_DIGITS"; then
    PHONE_CORRECT="true"
    echo "Phone number contains expected digits"
fi

# Escape special characters for JSON
CURRENT_EM_CONTACT_ESCAPED=$(echo "$CURRENT_EM_CONTACT" | sed 's/"/\\"/g' | tr '\n' ' ')
INITIAL_EM_CONTACT_ESCAPED=$(echo "$INITIAL_EM_CONTACT" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/emergency_contact_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "patient_name": "$CURRENT_FNAME $CURRENT_LNAME",
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_values": {
        "em_contact": "$INITIAL_EM_CONTACT_ESCAPED",
        "em_phone": "$INITIAL_EM_PHONE"
    },
    "current_values": {
        "em_contact": "$CURRENT_EM_CONTACT_ESCAPED",
        "em_phone": "$CURRENT_EM_PHONE",
        "em_phone_digits": "$CURRENT_EM_PHONE_DIGITS"
    },
    "changes": {
        "contact_changed": $CONTACT_CHANGED,
        "phone_changed": $PHONE_CHANGED,
        "record_modified_during_task": $RECORD_MODIFIED
    },
    "validation": {
        "contact_correct": $CONTACT_CORRECT,
        "phone_correct": $PHONE_CORRECT
    },
    "record_modified_timestamp": ${CURRENT_MODIFIED:-0},
    "initial_modified_timestamp": ${INITIAL_MODIFIED:-0},
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/emergency_contact_result.json 2>/dev/null || sudo rm -f /tmp/emergency_contact_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/emergency_contact_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/emergency_contact_result.json
chmod 666 /tmp/emergency_contact_result.json 2>/dev/null || sudo chmod 666 /tmp/emergency_contact_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/emergency_contact_result.json"
cat /tmp/emergency_contact_result.json

echo ""
echo "=== Export Complete ==="