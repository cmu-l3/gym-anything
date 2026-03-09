#!/bin/bash
set -e

echo "=== Exporting Configure Inbound Failover Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# QUERY DATABASE FOR FINAL STATE
# ------------------------------------------------------------------

# We use docker exec to query the database inside the container
# We construct a JSON object manually from the query result

echo "Querying Vicidial database..."

# Query specific fields for group SUPPORT
# Using -B (batch) -N (skip headers) for clean output
DB_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
SELECT 
    call_time_id,
    after_hours_action,
    after_hours_voicemail,
    no_agent_no_queue_action,
    no_agent_no_queue_action_value,
    wait_hold_option,
    wait_time_option_seconds,
    wait_time_option_value
FROM vicidial_inbound_groups 
WHERE group_id = 'SUPPORT';
" 2>/dev/null || true)

# Default values if query fails or returns empty
CALL_TIME_ID=""
AH_ACTION=""
AH_VM=""
NANQ_ACTION=""
NANQ_VALUE=""
WAIT_OPTION=""
WAIT_SECONDS="0"
WAIT_VALUE=""

if [ -n "$DB_RESULT" ]; then
    # Parse tab-separated values
    CALL_TIME_ID=$(echo "$DB_RESULT" | cut -f1)
    AH_ACTION=$(echo "$DB_RESULT" | cut -f2)
    AH_VM=$(echo "$DB_RESULT" | cut -f3)
    NANQ_ACTION=$(echo "$DB_RESULT" | cut -f4)
    NANQ_VALUE=$(echo "$DB_RESULT" | cut -f5)
    WAIT_OPTION=$(echo "$DB_RESULT" | cut -f6)
    WAIT_SECONDS=$(echo "$DB_RESULT" | cut -f7)
    WAIT_VALUE=$(echo "$DB_RESULT" | cut -f8)
fi

# Check Modification Time (Anti-Gaming)
# We can check the 'last_modified' timestamp in DB if available, but vicidial tables 
# might not strictly track this in a standard column for every edit.
# Instead, we rely on the fact that the setup script reset the values to defaults.
# If they match the target now, the agent must have changed them.

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "group_id": "SUPPORT",
    "final_state": {
        "call_time_id": "$CALL_TIME_ID",
        "after_hours_action": "$AH_ACTION",
        "after_hours_voicemail": "$AH_VM",
        "no_agent_no_queue_action": "$NANQ_ACTION",
        "no_agent_no_queue_action_value": "$NANQ_VALUE",
        "wait_hold_option": "$WAIT_OPTION",
        "wait_time_option_seconds": $WAIT_SECONDS,
        "wait_time_option_value": "$WAIT_VALUE"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="