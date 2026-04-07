#!/bin/bash
# Export script for Assign Primary Care Provider Task

echo "=== Exporting Assign Primary Care Provider Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=3

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get initial and expected values
INITIAL_PROVIDER_ID=$(cat /tmp/initial_provider_id.txt 2>/dev/null || echo "0")
EXPECTED_PROVIDER_ID=$(cat /tmp/expected_provider_id.txt 2>/dev/null || echo "0")

echo "Initial provider ID: $INITIAL_PROVIDER_ID"
echo "Expected provider ID: $EXPECTED_PROVIDER_ID"

# Query current provider assignment
echo ""
echo "=== Querying current provider assignment ==="
CURRENT_PROVIDER_ID=$(openemr_query "SELECT COALESCE(providerID, 0) FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Current providerID: $CURRENT_PROVIDER_ID"

# Get patient details
PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB, providerID FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Patient record: $PATIENT_DATA"

# Get provider details if assigned
PROVIDER_DATA=""
PROVIDER_FNAME=""
PROVIDER_LNAME=""
PROVIDER_USERNAME=""
PROVIDER_FOUND="false"

if [ "$CURRENT_PROVIDER_ID" != "0" ] && [ -n "$CURRENT_PROVIDER_ID" ]; then
    PROVIDER_DATA=$(openemr_query "SELECT id, username, fname, lname FROM users WHERE id=$CURRENT_PROVIDER_ID" 2>/dev/null)
    if [ -n "$PROVIDER_DATA" ]; then
        PROVIDER_FOUND="true"
        PROVIDER_ID_FROM_DB=$(echo "$PROVIDER_DATA" | cut -f1)
        PROVIDER_USERNAME=$(echo "$PROVIDER_DATA" | cut -f2)
        PROVIDER_FNAME=$(echo "$PROVIDER_DATA" | cut -f3)
        PROVIDER_LNAME=$(echo "$PROVIDER_DATA" | cut -f4)
        echo "Assigned provider: $PROVIDER_FNAME $PROVIDER_LNAME (username: $PROVIDER_USERNAME)"
    fi
fi

# Check if provider was changed during task (anti-gaming)
PROVIDER_CHANGED="false"
if [ "$CURRENT_PROVIDER_ID" != "$INITIAL_PROVIDER_ID" ] && [ "$CURRENT_PROVIDER_ID" != "0" ]; then
    PROVIDER_CHANGED="true"
    echo "Provider was changed during task"
elif [ "$CURRENT_PROVIDER_ID" == "$INITIAL_PROVIDER_ID" ] && [ "$INITIAL_PROVIDER_ID" != "0" ]; then
    echo "WARNING: Provider was already set before task started (possible gaming)"
else
    echo "Provider was NOT changed (still NULL or 0)"
fi

# Check if correct provider was assigned
CORRECT_PROVIDER="false"
if [ "$CURRENT_PROVIDER_ID" == "$EXPECTED_PROVIDER_ID" ]; then
    CORRECT_PROVIDER="true"
    echo "Correct provider (Philip Katz) was assigned"
else
    echo "Incorrect or no provider assigned (expected ID: $EXPECTED_PROVIDER_ID, got: $CURRENT_PROVIDER_ID)"
fi

# Escape special characters for JSON
PROVIDER_FNAME_ESCAPED=$(echo "$PROVIDER_FNAME" | sed 's/"/\\"/g')
PROVIDER_LNAME_ESCAPED=$(echo "$PROVIDER_LNAME" | sed 's/"/\\"/g')
PROVIDER_USERNAME_ESCAPED=$(echo "$PROVIDER_USERNAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/assign_pcp_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_provider_id": $INITIAL_PROVIDER_ID,
    "expected_provider_id": $EXPECTED_PROVIDER_ID,
    "current_provider_id": $CURRENT_PROVIDER_ID,
    "provider_changed": $PROVIDER_CHANGED,
    "correct_provider_assigned": $CORRECT_PROVIDER,
    "assigned_provider": {
        "found": $PROVIDER_FOUND,
        "id": "$CURRENT_PROVIDER_ID",
        "username": "$PROVIDER_USERNAME_ESCAPED",
        "fname": "$PROVIDER_FNAME_ESCAPED",
        "lname": "$PROVIDER_LNAME_ESCAPED"
    },
    "screenshot_final": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/assign_pcp_result.json 2>/dev/null || sudo rm -f /tmp/assign_pcp_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/assign_pcp_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/assign_pcp_result.json
chmod 666 /tmp/assign_pcp_result.json 2>/dev/null || sudo chmod 666 /tmp/assign_pcp_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/assign_pcp_result.json"
cat /tmp/assign_pcp_result.json

echo ""
echo "=== Export Complete ==="