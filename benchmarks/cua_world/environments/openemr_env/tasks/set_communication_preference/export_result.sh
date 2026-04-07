#!/bin/bash
# Export script for Set Communication Preference Task

echo "=== Exporting Communication Preference Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=5

# Get task timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Load initial preferences
INITIAL_ALLOWEMAIL=""
INITIAL_VOICE=""
if [ -f /tmp/initial_hipaa_prefs.json ]; then
    INITIAL_ALLOWEMAIL=$(grep -o '"hipaa_allowemail": "[^"]*"' /tmp/initial_hipaa_prefs.json | cut -d'"' -f4)
    INITIAL_VOICE=$(grep -o '"hipaa_voice": "[^"]*"' /tmp/initial_hipaa_prefs.json | cut -d'"' -f4)
fi
echo "Initial values - allowemail: '$INITIAL_ALLOWEMAIL', voice: '$INITIAL_VOICE'"

# Get current HIPAA preferences from database
echo ""
echo "=== Querying current HIPAA preferences for patient PID=$PATIENT_PID ==="
CURRENT_PREFS=$(openemr_query "SELECT hipaa_allowemail, hipaa_voice, hipaa_allowsms, hipaa_mail, hipaa_message, hipaa_notice FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Current preferences (raw): $CURRENT_PREFS"

# Parse current values
CURRENT_ALLOWEMAIL=$(echo "$CURRENT_PREFS" | cut -f1)
CURRENT_VOICE=$(echo "$CURRENT_PREFS" | cut -f2)
CURRENT_ALLOWSMS=$(echo "$CURRENT_PREFS" | cut -f3)
CURRENT_MAIL=$(echo "$CURRENT_PREFS" | cut -f4)
CURRENT_MESSAGE=$(echo "$CURRENT_PREFS" | cut -f5)
CURRENT_NOTICE=$(echo "$CURRENT_PREFS" | cut -f6)

echo "Parsed values:"
echo "  hipaa_allowemail: '$CURRENT_ALLOWEMAIL'"
echo "  hipaa_voice: '$CURRENT_VOICE'"
echo "  hipaa_allowsms: '$CURRENT_ALLOWSMS'"
echo "  hipaa_mail: '$CURRENT_MAIL'"

# Get current patient record modification date
CURRENT_DATE=$(openemr_query "SELECT date FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
INITIAL_DATE=$(cat /tmp/initial_patient_date 2>/dev/null || echo "")
echo "Patient record date - initial: '$INITIAL_DATE', current: '$CURRENT_DATE'"

# Determine if record was modified
RECORD_MODIFIED="false"
if [ "$CURRENT_DATE" != "$INITIAL_DATE" ] && [ -n "$CURRENT_DATE" ]; then
    RECORD_MODIFIED="true"
    echo "Patient record WAS modified"
else
    echo "Patient record was NOT modified (dates match or empty)"
fi

# Check if preferences changed
EMAIL_CHANGED="false"
VOICE_CHANGED="false"

if [ "$CURRENT_ALLOWEMAIL" != "$INITIAL_ALLOWEMAIL" ]; then
    EMAIL_CHANGED="true"
    echo "Email preference changed: '$INITIAL_ALLOWEMAIL' -> '$CURRENT_ALLOWEMAIL'"
fi

if [ "$CURRENT_VOICE" != "$INITIAL_VOICE" ]; then
    VOICE_CHANGED="true"
    echo "Voice preference changed: '$INITIAL_VOICE' -> '$CURRENT_VOICE'"
fi

# Verify expected values
# Expected: hipaa_allowemail = YES, hipaa_voice = NO
EMAIL_CORRECT="false"
VOICE_CORRECT="false"

# Normalize values for comparison (uppercase)
CURRENT_ALLOWEMAIL_UPPER=$(echo "$CURRENT_ALLOWEMAIL" | tr '[:lower:]' '[:upper:]')
CURRENT_VOICE_UPPER=$(echo "$CURRENT_VOICE" | tr '[:lower:]' '[:upper:]')

if [ "$CURRENT_ALLOWEMAIL_UPPER" = "YES" ]; then
    EMAIL_CORRECT="true"
    echo "Email preference is correct (YES)"
else
    echo "Email preference incorrect: expected YES, got '$CURRENT_ALLOWEMAIL'"
fi

if [ "$CURRENT_VOICE_UPPER" = "NO" ]; then
    VOICE_CORRECT="true"
    echo "Voice preference is correct (NO)"
else
    echo "Voice preference incorrect: expected NO, got '$CURRENT_VOICE'"
fi

# Get patient info for verification
PATIENT_INFO=$(openemr_query "SELECT fname, lname, email FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
PATIENT_FNAME=$(echo "$PATIENT_INFO" | cut -f1)
PATIENT_LNAME=$(echo "$PATIENT_INFO" | cut -f2)
PATIENT_EMAIL=$(echo "$PATIENT_INFO" | cut -f3)

# Escape special characters for JSON
PATIENT_EMAIL_ESCAPED=$(echo "$PATIENT_EMAIL" | sed 's/"/\\"/g')
CURRENT_MESSAGE_ESCAPED=$(echo "$CURRENT_MESSAGE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/comm_pref_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "patient_fname": "$PATIENT_FNAME",
    "patient_lname": "$PATIENT_LNAME",
    "patient_email": "$PATIENT_EMAIL_ESCAPED",
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_values": {
        "hipaa_allowemail": "$INITIAL_ALLOWEMAIL",
        "hipaa_voice": "$INITIAL_VOICE"
    },
    "current_values": {
        "hipaa_allowemail": "$CURRENT_ALLOWEMAIL",
        "hipaa_voice": "$CURRENT_VOICE",
        "hipaa_allowsms": "$CURRENT_ALLOWSMS",
        "hipaa_mail": "$CURRENT_MAIL",
        "hipaa_message": "$CURRENT_MESSAGE_ESCAPED",
        "hipaa_notice": "$CURRENT_NOTICE"
    },
    "validation": {
        "record_modified": $RECORD_MODIFIED,
        "email_preference_changed": $EMAIL_CHANGED,
        "voice_preference_changed": $VOICE_CHANGED,
        "email_value_correct": $EMAIL_CORRECT,
        "voice_value_correct": $VOICE_CORRECT
    },
    "record_dates": {
        "initial": "$INITIAL_DATE",
        "current": "$CURRENT_DATE"
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/comm_pref_result.json 2>/dev/null || sudo rm -f /tmp/comm_pref_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/comm_pref_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/comm_pref_result.json
chmod 666 /tmp/comm_pref_result.json 2>/dev/null || sudo chmod 666 /tmp/comm_pref_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/comm_pref_result.json
echo ""
echo "=== Export Complete ==="