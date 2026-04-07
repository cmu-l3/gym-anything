#!/bin/bash
# Export script for Grant Patient Portal Access task

echo "=== Exporting Grant Portal Access Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png
sleep 1

# Target patient
PATIENT_PID=2

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get initial portal status
INITIAL_STATUS=$(cat /tmp/initial_portal_status.txt 2>/dev/null || echo "unknown")
echo "Initial portal status was: $INITIAL_STATUS"

# Query current portal status for the patient
echo ""
echo "=== Querying current portal status for PID=$PATIENT_PID ==="
CURRENT_PORTAL_DATA=$(openemr_query "SELECT allow_patient_portal, portal_username, portal_pwd_status FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Current portal data: $CURRENT_PORTAL_DATA"

# Parse portal data
PORTAL_ENABLED=""
PORTAL_USERNAME=""
PORTAL_PWD_STATUS=""

if [ -n "$CURRENT_PORTAL_DATA" ]; then
    PORTAL_ENABLED=$(echo "$CURRENT_PORTAL_DATA" | cut -f1)
    PORTAL_USERNAME=$(echo "$CURRENT_PORTAL_DATA" | cut -f2)
    PORTAL_PWD_STATUS=$(echo "$CURRENT_PORTAL_DATA" | cut -f3)
fi

echo "Parsed values:"
echo "  Portal enabled: '$PORTAL_ENABLED'"
echo "  Portal username: '$PORTAL_USERNAME'"
echo "  Portal pwd status: '$PORTAL_PWD_STATUS'"

# Also get full patient record to check modification
PATIENT_RECORD=$(openemr_query "SELECT pid, fname, lname, allow_patient_portal, portal_username FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Full patient record: $PATIENT_RECORD"

# Check if portal was enabled (YES or 1)
PORTAL_IS_ENABLED="false"
PORTAL_ENABLED_UPPER=$(echo "$PORTAL_ENABLED" | tr '[:lower:]' '[:upper:]')
if [ "$PORTAL_ENABLED_UPPER" = "YES" ] || [ "$PORTAL_ENABLED" = "1" ]; then
    PORTAL_IS_ENABLED="true"
    echo "Portal access IS enabled"
else
    echo "Portal access is NOT enabled (value: '$PORTAL_ENABLED')"
fi

# Check if username matches expected
EXPECTED_USERNAME="angila.fadel"
USERNAME_MATCHES="false"
PORTAL_USERNAME_LOWER=$(echo "$PORTAL_USERNAME" | tr '[:upper:]' '[:lower:]')
EXPECTED_USERNAME_LOWER=$(echo "$EXPECTED_USERNAME" | tr '[:upper:]' '[:lower:]')
if [ "$PORTAL_USERNAME_LOWER" = "$EXPECTED_USERNAME_LOWER" ]; then
    USERNAME_MATCHES="true"
    echo "Portal username matches expected: $EXPECTED_USERNAME"
else
    echo "Portal username mismatch: expected '$EXPECTED_USERNAME', got '$PORTAL_USERNAME'"
fi

# Check if there's any portal username set at all
USERNAME_SET="false"
if [ -n "$PORTAL_USERNAME" ] && [ "$PORTAL_USERNAME" != "NULL" ]; then
    USERNAME_SET="true"
fi

# Check if record was modified during task window
RECORD_MODIFIED="false"
# Check by comparing portal values - if they changed from initial, record was modified
INITIAL_PORTAL_ENABLED=$(echo "$INITIAL_STATUS" | cut -f1)
if [ "$PORTAL_ENABLED" != "$INITIAL_PORTAL_ENABLED" ] || [ -n "$PORTAL_USERNAME" ]; then
    if [ "$PORTAL_IS_ENABLED" = "true" ]; then
        RECORD_MODIFIED="true"
        echo "Record was modified during task (portal enabled changed)"
    fi
fi

# Check if Firefox is still running (indicates workflow was done in browser)
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    FIREFOX_RUNNING="true"
fi

# Escape special characters for JSON
PORTAL_USERNAME_ESCAPED=$(echo "$PORTAL_USERNAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/portal_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "portal_status": {
        "allow_patient_portal": "$PORTAL_ENABLED",
        "portal_enabled": $PORTAL_IS_ENABLED,
        "portal_username": "$PORTAL_USERNAME_ESCAPED",
        "username_matches_expected": $USERNAME_MATCHES,
        "username_set": $USERNAME_SET,
        "portal_pwd_status": "$PORTAL_PWD_STATUS"
    },
    "validation": {
        "record_modified": $RECORD_MODIFIED,
        "portal_enabled": $PORTAL_IS_ENABLED,
        "correct_username": $USERNAME_MATCHES
    },
    "browser_running": $FIREFOX_RUNNING,
    "screenshot_final": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/portal_access_result.json 2>/dev/null || sudo rm -f /tmp/portal_access_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/portal_access_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/portal_access_result.json
chmod 666 /tmp/portal_access_result.json 2>/dev/null || sudo chmod 666 /tmp/portal_access_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/portal_access_result.json"
cat /tmp/portal_access_result.json

echo ""
echo "=== Export Complete ==="