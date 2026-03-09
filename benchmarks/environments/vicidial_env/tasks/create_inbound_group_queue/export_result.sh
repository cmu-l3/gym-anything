#!/bin/bash
set -e

echo "=== Exporting Create Inbound Group Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query the database for the specific group ID 'RECALL01'
# We select the specific columns required for verification
echo "Querying Vicidial database for RECALL01..."

QUERY="SELECT group_id, group_name, group_color, active, queue_priority, \
next_agent_call, fronter_display, ingroup_recording_override, \
drop_call_seconds, after_hours_action \
FROM vicidial_inbound_groups \
WHERE group_id='RECALL01';"

# Execute query inside docker and output as tab-separated values (TSV)
# We use -N to skip headers so we just get the data row
DB_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "$QUERY" 2>/dev/null || echo "")

# 4. Parse result
FOUND="false"
GROUP_DATA="{}"

if [ -n "$DB_RESULT" ]; then
    FOUND="true"
    
    # Read TSV into variables
    # Note: We use awk or cut to handle potential spaces in group_name safely
    
    g_id=$(echo "$DB_RESULT" | cut -f1)
    g_name=$(echo "$DB_RESULT" | cut -f2)
    g_color=$(echo "$DB_RESULT" | cut -f3)
    g_active=$(echo "$DB_RESULT" | cut -f4)
    g_priority=$(echo "$DB_RESULT" | cut -f5)
    g_next_agent=$(echo "$DB_RESULT" | cut -f6)
    g_fronter=$(echo "$DB_RESULT" | cut -f7)
    g_recording=$(echo "$DB_RESULT" | cut -f8)
    g_drop=$(echo "$DB_RESULT" | cut -f9)
    g_after=$(echo "$DB_RESULT" | cut -f10)

    # Construct JSON object for the group data
    # We use python to safely dump the JSON to handle escaping quotes/special chars
    GROUP_DATA=$(python3 -c "import json; print(json.dumps({
        'group_id': '$g_id',
        'group_name': '$g_name',
        'group_color': '$g_color',
        'active': '$g_active',
        'queue_priority': '$g_priority',
        'next_agent_call': '$g_next_agent',
        'fronter_display': '$g_fronter',
        'ingroup_recording_override': '$g_recording',
        'drop_call_seconds': '$g_drop',
        'after_hours_action': '$g_after'
    }))")
fi

# 5. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "group_found": $FOUND,
    "group_data": $GROUP_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to shared location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="