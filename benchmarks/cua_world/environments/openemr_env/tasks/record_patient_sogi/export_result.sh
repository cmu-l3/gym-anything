#!/bin/bash
# Export script for Record Patient SOGI Task

echo "=== Exporting Record Patient SOGI Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=6

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_MODIFIED=$(cat /tmp/initial_modified_timestamp 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"

# Get initial SOGI state
INITIAL_SOGI=$(cat /tmp/initial_sogi_state 2>/dev/null || echo "")
echo "Initial SOGI state: $INITIAL_SOGI"

# Query current SOGI values
echo ""
echo "=== Querying current SOGI values for patient PID=$PATIENT_PID ==="
CURRENT_SOGI=$(openemr_query "SELECT sexual_orientation, gender_identity, sex FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Current SOGI state: $CURRENT_SOGI"

# Parse current values (tab-separated)
SEXUAL_ORIENTATION=$(echo "$CURRENT_SOGI" | cut -f1)
GENDER_IDENTITY=$(echo "$CURRENT_SOGI" | cut -f2)
SEX=$(echo "$CURRENT_SOGI" | cut -f3)

echo "Parsed values:"
echo "  Sexual Orientation: '$SEXUAL_ORIENTATION'"
echo "  Gender Identity: '$GENDER_IDENTITY'"
echo "  Sex: '$SEX'"

# Get current modified timestamp
CURRENT_MODIFIED=$(openemr_query "SELECT UNIX_TIMESTAMP(date) as modified_ts FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Current modified timestamp: $CURRENT_MODIFIED"

# Check if record was modified during task
RECORD_MODIFIED="false"
if [ -n "$CURRENT_MODIFIED" ] && [ "$CURRENT_MODIFIED" != "NULL" ] && [ "$CURRENT_MODIFIED" -gt "$TASK_START" ]; then
    RECORD_MODIFIED="true"
    echo "Record was modified during task"
else
    echo "Record may not have been modified during task"
fi

# Check if SOGI values changed from initial state
SOGI_CHANGED="false"
if [ "$CURRENT_SOGI" != "$INITIAL_SOGI" ]; then
    SOGI_CHANGED="true"
    echo "SOGI values changed from initial state"
fi

# Validate sexual orientation value
SO_VALID="false"
SO_LOWER=$(echo "$SEXUAL_ORIENTATION" | tr '[:upper:]' '[:lower:]')
if echo "$SO_LOWER" | grep -qiE "(bisexual|bi)"; then
    SO_VALID="true"
    echo "Sexual orientation matches expected value (bisexual)"
fi

# Validate gender identity value
GI_VALID="false"
GI_LOWER=$(echo "$GENDER_IDENTITY" | tr '[:upper:]' '[:lower:]')
if echo "$GI_LOWER" | grep -qiE "(male|identifies.as.male|identifies_as_male)"; then
    GI_VALID="true"
    echo "Gender identity matches expected value (identifies as male)"
fi

# Validate sex value
SEX_VALID="false"
SEX_LOWER=$(echo "$SEX" | tr '[:upper:]' '[:lower:]')
if echo "$SEX_LOWER" | grep -qiE "^(male|m)$"; then
    SEX_VALID="true"
    echo "Sex matches expected value (male)"
fi

# Get full patient record for verification
FULL_PATIENT=$(openemr_query "SELECT pid, fname, lname, DOB, sex, sexual_orientation, gender_identity FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo ""
echo "Full patient record: $FULL_PATIENT"

# Escape special characters for JSON
SEXUAL_ORIENTATION_ESC=$(echo "$SEXUAL_ORIENTATION" | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
GENDER_IDENTITY_ESC=$(echo "$GENDER_IDENTITY" | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
SEX_ESC=$(echo "$SEX" | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/[[:space:]]*$//')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/sogi_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_modified_timestamp": ${INITIAL_MODIFIED:-0},
    "current_modified_timestamp": ${CURRENT_MODIFIED:-0},
    "record_modified_during_task": $RECORD_MODIFIED,
    "sogi_values_changed": $SOGI_CHANGED,
    "current_values": {
        "sexual_orientation": "$SEXUAL_ORIENTATION_ESC",
        "gender_identity": "$GENDER_IDENTITY_ESC",
        "sex": "$SEX_ESC"
    },
    "validation": {
        "sexual_orientation_valid": $SO_VALID,
        "gender_identity_valid": $GI_VALID,
        "sex_valid": $SEX_VALID
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location
rm -f /tmp/sogi_task_result.json 2>/dev/null || sudo rm -f /tmp/sogi_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/sogi_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/sogi_task_result.json
chmod 666 /tmp/sogi_task_result.json 2>/dev/null || sudo chmod 666 /tmp/sogi_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/sogi_task_result.json"
cat /tmp/sogi_task_result.json

echo ""
echo "=== Export Complete ==="