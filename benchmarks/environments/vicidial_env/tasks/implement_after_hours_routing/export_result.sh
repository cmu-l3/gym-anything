#!/bin/bash
set -e
echo "=== Exporting Implement After-Hours Routing result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the final state
# We need data from two tables: vicidial_call_times and vicidial_inbound_groups

echo "Querying Vicidial database..."

# 1. Get Call Time details (PRISUP_HRS)
# Using -r (raw) and jq to format as JSON would be ideal, but we'll manually construct or use python if jq is missing inside container.
# We will pull raw fields and construct JSON locally.

CALL_TIME_DATA=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
    SELECT call_time_id, call_time_name, ct_default_start, ct_default_stop, ct_saturday_start, ct_saturday_stop, ct_sunday_start, ct_sunday_stop 
    FROM vicidial_call_times 
    WHERE call_time_id='PRISUP_HRS'
" 2>/dev/null || true)

# 2. Get Inbound Group details (PRISUP)
GROUP_DATA=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
    SELECT group_id, call_time_id, after_hours_action, after_hours_voicemail, after_hours_message 
    FROM vicidial_inbound_groups 
    WHERE group_id='PRISUP'
" 2>/dev/null || true)

# Parse Call Time Data
# Format: id name start stop sat_start sat_stop sun_start sun_stop
CT_EXISTS="false"
CT_START=""
CT_STOP=""
CT_SAT_START=""
CT_SAT_STOP=""
CT_SUN_START=""
CT_SUN_STOP=""

if [ -n "$CALL_TIME_DATA" ]; then
    CT_EXISTS="true"
    # Read tab-separated values into array
    IFS=$'\t' read -r -a CT_FIELDS <<< "$CALL_TIME_DATA"
    CT_START="${CT_FIELDS[2]}"
    CT_STOP="${CT_FIELDS[3]}"
    CT_SAT_START="${CT_FIELDS[4]}"
    CT_SAT_STOP="${CT_FIELDS[5]}"
    CT_SUN_START="${CT_FIELDS[6]}"
    CT_SUN_STOP="${CT_FIELDS[7]}"
fi

# Parse Group Data
# Format: group_id call_time_id action voicemail message
GRP_EXISTS="false"
GRP_TIME_ID=""
GRP_ACTION=""
GRP_VOICEMAIL=""
GRP_MESSAGE=""

if [ -n "$GROUP_DATA" ]; then
    GRP_EXISTS="true"
    IFS=$'\t' read -r -a GRP_FIELDS <<< "$GROUP_DATA"
    GRP_TIME_ID="${GRP_FIELDS[1]}"
    GRP_ACTION="${GRP_FIELDS[2]}"
    GRP_VOICEMAIL="${GRP_FIELDS[3]}"
    GRP_MESSAGE="${GRP_FIELDS[4]}"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "call_time": {
        "exists": $CT_EXISTS,
        "default_start": "$CT_START",
        "default_stop": "$CT_STOP",
        "saturday_start": "$CT_SAT_START",
        "saturday_stop": "$CT_SAT_STOP",
        "sunday_start": "$CT_SUN_START",
        "sunday_stop": "$CT_SUN_STOP"
    },
    "inbound_group": {
        "exists": $GRP_EXISTS,
        "call_time_id": "$GRP_TIME_ID",
        "action": "$GRP_ACTION",
        "voicemail": "$GRP_VOICEMAIL",
        "message": "$GRP_MESSAGE"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="