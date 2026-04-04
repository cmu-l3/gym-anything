#!/bin/bash
set -e
echo "=== Exporting task results: activate_emergency_closure ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query Database for results
# We need to check two tables: vicidial_call_times and vicidial_inbound_groups

echo "Querying database..."

# 1. Get Call Time details for FORCE_CLOSE
CALL_TIME_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
SELECT CONCAT(
    '{\"exists\": true, ',
    '\"ct_default_start\": \"', ct_default_start, '\", ',
    '\"ct_default_stop\": \"', ct_default_stop, '\"}'
)
FROM vicidial_call_times 
WHERE call_time_id='FORCE_CLOSE' LIMIT 1;" 2>/dev/null || echo "{\"exists\": false}")

if [ -z "$CALL_TIME_JSON" ]; then
    CALL_TIME_JSON="{\"exists\": false}"
fi

# 2. Get Inbound Group details for CS_QUEUE
GROUP_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
SELECT CONCAT(
    '{\"exists\": true, ',
    '\"call_time_id\": \"', call_time_id, '\", ',
    '\"after_hours_action\": \"', after_hours_action, '\", ',
    '\"after_hours_message_filename\": \"', IFNULL(after_hours_message_filename, ''), '\"}'
)
FROM vicidial_inbound_groups 
WHERE group_id='CS_QUEUE' LIMIT 1;" 2>/dev/null || echo "{\"exists\": false}")

if [ -z "$GROUP_JSON" ]; then
    GROUP_JSON="{\"exists\": false}"
fi

# 3. Check timestamps (Anti-gaming)
# We check if the modification time in the DB is after task start
# Vicidial doesn't always store exact mod times easily accessible, so we rely on state diff from setup
# But we can check if the record exists now and didn't before (handled by setup script clearing it)

# Combine into result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "call_time": $CALL_TIME_JSON,
    "inbound_group": $GROUP_JSON,
    "timestamp": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json