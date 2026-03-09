#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query System Settings (allow_chats)
# We use -N (skip column headers) and -B (batch/tab-separated) for easier parsing, 
# but for single value -N is sufficient.
ALLOW_CHATS_VAL=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT allow_chats FROM system_settings LIMIT 1;" 2>/dev/null || echo "ERROR")

# 2. Query the Chat Group
# We select specific fields to verify configuration
GROUP_DATA=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT group_name, active, group_color, welcome_message FROM vicidial_chat_groups WHERE group_id='TECHSUP';" 2>/dev/null || echo "")

GROUP_EXISTS="false"
GROUP_NAME=""
GROUP_ACTIVE=""
GROUP_COLOR=""
GROUP_MSG=""

if [ -n "$GROUP_DATA" ]; then
    GROUP_EXISTS="true"
    # Parse tab-separated values
    GROUP_NAME=$(echo "$GROUP_DATA" | awk -F'\t' '{print $1}')
    GROUP_ACTIVE=$(echo "$GROUP_DATA" | awk -F'\t' '{print $2}')
    GROUP_COLOR=$(echo "$GROUP_DATA" | awk -F'\t' '{print $3}')
    GROUP_MSG=$(echo "$GROUP_DATA" | awk -F'\t' '{print $4}')
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare JSON Result
# Using python to safely construct JSON to handle potential special characters in user input
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'allow_chats_setting': '$ALLOW_CHATS_VAL',
    'group_exists': $GROUP_EXISTS,
    'group_details': {
        'name': '''$GROUP_NAME''',
        'active': '$GROUP_ACTIVE',
        'color': '$GROUP_COLOR',
        'welcome_message': '''$GROUP_MSG'''
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="