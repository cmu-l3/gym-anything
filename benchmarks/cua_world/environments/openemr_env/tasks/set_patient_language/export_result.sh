#!/bin/bash
# Export script for Set Patient Language Task

echo "=== Exporting Set Patient Language Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot first
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_screenshot.png

# Target patient
PATIENT_PID=3

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial language value
INITIAL_LANGUAGE=$(cat /tmp/initial_language.txt 2>/dev/null || echo "")

# Query current language value
echo "Querying current language preference..."
CURRENT_LANGUAGE=$(openemr_query "SELECT COALESCE(language, '') FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null | tr -d '\n')

echo "Language comparison:"
echo "  Initial: '$INITIAL_LANGUAGE'"
echo "  Current: '$CURRENT_LANGUAGE'"

# Check if language was changed
LANGUAGE_CHANGED="false"
if [ "$CURRENT_LANGUAGE" != "$INITIAL_LANGUAGE" ] && [ -n "$CURRENT_LANGUAGE" ]; then
    LANGUAGE_CHANGED="true"
    echo "Language was changed!"
else
    echo "Language was NOT changed"
fi

# Check if language is Spanish (case-insensitive)
IS_SPANISH="false"
CURRENT_LOWER=$(echo "$CURRENT_LANGUAGE" | tr '[:upper:]' '[:lower:]')
if echo "$CURRENT_LOWER" | grep -qE "^(spanish|spa|es|español)"; then
    IS_SPANISH="true"
    echo "Language is set to Spanish variant: '$CURRENT_LANGUAGE'"
elif echo "$CURRENT_LOWER" | grep -qi "spanish"; then
    IS_SPANISH="true"
    echo "Language contains 'spanish': '$CURRENT_LANGUAGE'"
fi

# Get full patient record for verification
echo ""
echo "=== Current patient record ==="
PATIENT_RECORD=$(openemr_query "SELECT pid, fname, lname, language FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "$PATIENT_RECORD"

# Parse patient data
PATIENT_FNAME=$(echo "$PATIENT_RECORD" | cut -f2)
PATIENT_LNAME=$(echo "$PATIENT_RECORD" | cut -f3)

# Check if patient was accessed (by looking at recent form activity, if available)
# This is a secondary check to ensure agent actually navigated to the patient
PATIENT_ACCESSED="unknown"

# Verify correct patient
CORRECT_PATIENT="false"
if [ "$PATIENT_PID" = "3" ]; then
    CORRECT_PATIENT="true"
fi

# Escape special characters for JSON
INITIAL_LANGUAGE_ESCAPED=$(echo "$INITIAL_LANGUAGE" | sed 's/"/\\"/g' | tr '\n' ' ')
CURRENT_LANGUAGE_ESCAPED=$(echo "$CURRENT_LANGUAGE" | sed 's/"/\\"/g' | tr '\n' ' ')
PATIENT_FNAME_ESCAPED=$(echo "$PATIENT_FNAME" | sed 's/"/\\"/g')
PATIENT_LNAME_ESCAPED=$(echo "$PATIENT_LNAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/language_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "patient": {
        "pid": $PATIENT_PID,
        "fname": "$PATIENT_FNAME_ESCAPED",
        "lname": "$PATIENT_LNAME_ESCAPED"
    },
    "language": {
        "initial": "$INITIAL_LANGUAGE_ESCAPED",
        "current": "$CURRENT_LANGUAGE_ESCAPED",
        "was_changed": $LANGUAGE_CHANGED,
        "is_spanish": $IS_SPANISH
    },
    "validation": {
        "correct_patient": $CORRECT_PATIENT,
        "language_updated": $LANGUAGE_CHANGED,
        "language_is_spanish": $IS_SPANISH
    },
    "screenshots": {
        "initial": "/tmp/task_initial_screenshot.png",
        "final": "/tmp/task_final_screenshot.png"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/set_language_result.json 2>/dev/null || sudo rm -f /tmp/set_language_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/set_language_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/set_language_result.json
chmod 666 /tmp/set_language_result.json 2>/dev/null || sudo chmod 666 /tmp/set_language_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/set_language_result.json
echo ""
echo "=== Export Complete ==="