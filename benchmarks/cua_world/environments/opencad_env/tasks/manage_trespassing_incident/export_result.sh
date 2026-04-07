#!/bin/bash
echo "=== Exporting manage_trespassing_incident result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Parameters for search
CALLER="Foreman Mike"
LOCATION="Quarry Main Gate"

# 1. Search for the call in 'call_history' (Closed calls)
# We prioritize finding it here because the task goal is to CLOSE the call.
echo "Searching call_history..."
HISTORY_ID=$(opencad_db_query "SELECT call_id FROM call_history WHERE caller LIKE '%$CALLER%' AND call_location LIKE '%$LOCATION%' ORDER BY call_id DESC LIMIT 1")

# 2. Search for the call in 'calls' (Active calls)
# If found here, the agent failed the "Close" step but might have done the others.
echo "Searching active calls..."
ACTIVE_ID=$(opencad_db_query "SELECT call_id FROM calls WHERE caller LIKE '%$CALLER%' AND call_location LIKE '%$LOCATION%' ORDER BY call_id DESC LIMIT 1")

FOUND_LOCATION="none"
CALL_ID=""
CALL_DESC=""
CALL_STATUS=""

if [ -n "$HISTORY_ID" ]; then
    FOUND_LOCATION="history"
    CALL_ID="$HISTORY_ID"
    # Get details from history
    CALL_DESC=$(opencad_db_query "SELECT call_description FROM call_history WHERE call_id=$CALL_ID")
    # History tables usually imply closed, but check status column if exists, otherwise assume 'Closed'
    CALL_STATUS=$(opencad_db_query "SELECT status FROM call_history WHERE call_id=$CALL_ID" 2>/dev/null)
    [ -z "$CALL_STATUS" ] && CALL_STATUS="Closed"
elif [ -n "$ACTIVE_ID" ]; then
    FOUND_LOCATION="active"
    CALL_ID="$ACTIVE_ID"
    # Get details from active table
    CALL_DESC=$(opencad_db_query "SELECT call_description FROM calls WHERE call_id=$CALL_ID")
    CALL_STATUS=$(opencad_db_query "SELECT status FROM calls WHERE call_id=$CALL_ID" 2>/dev/null)
    [ -z "$CALL_STATUS" ] && CALL_STATUS="Active"
fi

# JSON Escape
CALLER_ESC=$(json_escape "$CALLER")
LOCATION_ESC=$(json_escape "$LOCATION")
DESC_ESC=$(json_escape "$CALL_DESC")
STATUS_ESC=$(json_escape "$CALL_STATUS")

# Construct Result JSON
RESULT_JSON=$(cat << EOF
{
    "found_location": "$FOUND_LOCATION",
    "call_id": "$CALL_ID",
    "caller": "$CALLER_ESC",
    "location": "$LOCATION_ESC",
    "description": "$DESC_ESC",
    "status": "$STATUS_ESC",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="