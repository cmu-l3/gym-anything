#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure CAB Result ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for CAB Definition
# Tables involved:
# - cabdefinition: holds CAB names
# - cabmember: links cab_id to user_id
# - aaauser: holds user names

echo "Querying database for CAB..."

# Get CAB ID for the specific name
CAB_ID=$(sdp_db_exec "SELECT cab_id FROM cabdefinition WHERE lower(cab_name) = 'technical infrastructure cab';" 2>/dev/null)

CAB_EXISTS="false"
CAB_NAME=""
CAB_DESC=""
MEMBER_NAMES_JSON="[]"

if [ -n "$CAB_ID" ] && [ "$CAB_ID" != "" ]; then
    CAB_EXISTS="true"
    
    # Get details
    CAB_NAME=$(sdp_db_exec "SELECT cab_name FROM cabdefinition WHERE cab_id = $CAB_ID;" 2>/dev/null)
    CAB_DESC=$(sdp_db_exec "SELECT description FROM cabdefinition WHERE cab_id = $CAB_ID;" 2>/dev/null)
    
    # Get Members
    # Join cabmember -> aaauser (or sduser)
    # Note: Schema varies slightly by version, standard JOIN:
    # SELECT au.first_name FROM cabmember cm JOIN aaauser au ON cm.user_id = au.user_id WHERE cm.cab_id = ...
    
    MEMBERS=$(sdp_db_exec "SELECT au.first_name || ' ' || au.last_name FROM cabmember cm JOIN aaauser au ON cm.user_id = au.user_id WHERE cm.cab_id = $CAB_ID;" 2>/dev/null)
    
    # Convert newline separated list to JSON array
    if [ -n "$MEMBERS" ]; then
        MEMBER_NAMES_JSON=$(echo "$MEMBERS" | jq -R -s -c 'split("\n") | map(select(length > 0))')
    fi
fi

# Get Initial/Final Counts for verification
INITIAL_COUNT=$(cat /tmp/initial_cab_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(sdp_db_exec "SELECT count(*) FROM cabdefinition;" 2>/dev/null || echo "0")
CREATED_DURING_TASK="false"
if [ "$FINAL_COUNT" -gt "$INITIAL_COUNT" ]; then
    CREATED_DURING_TASK="true"
fi

# Escape strings for JSON
safe_json_string() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r'
}

SAFE_CAB_NAME=$(safe_json_string "$CAB_NAME")
SAFE_CAB_DESC=$(safe_json_string "$CAB_DESC")

# Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "cab_exists": $CAB_EXISTS,
    "cab_name": "$SAFE_CAB_NAME",
    "cab_description": "$SAFE_CAB_DESC",
    "members": $MEMBER_NAMES_JSON,
    "created_during_task": $CREATED_DURING_TASK,
    "timestamp": $(date +%s)
}
EOF

echo "Result JSON generated:"
cat /tmp/task_result.json

echo "=== Export Complete ==="