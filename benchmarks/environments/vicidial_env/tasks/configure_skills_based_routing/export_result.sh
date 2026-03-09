#!/bin/bash
echo "=== Exporting Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Database State
echo "Querying database..."

# Query 1: Inbound Group Routing Method
GROUP_ROUTING=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT next_agent_call FROM vicidial_inbound_groups WHERE group_id='AGENTDIRECT';")

# Query 2: User Rank for the group
USER_RANK=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT group_rank FROM vicidial_inbound_group_agents WHERE user='6666' AND group_id='AGENTDIRECT';")

# Query 3: Check if user is actually allowed in the group (checkbox checked)
# If the row exists, it's allowed. If they unchecked it, the row might be deleted or handled differently depending on Vicidial version.
# Usually Vicidial keeps the row. We'll check if the row exists.
IS_ALLOWED=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT count(*) FROM vicidial_inbound_group_agents WHERE user='6666' AND group_id='AGENTDIRECT';")

# 2. Screenshot
take_screenshot /tmp/task_final.png

# 3. Prepare JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "final_routing_method": "${GROUP_ROUTING:-unknown}",
    "final_user_rank": "${USER_RANK:-0}",
    "is_user_allowed": $IS_ALLOWED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported Data:"
cat /tmp/task_result.json
echo "=== Export Complete ==="