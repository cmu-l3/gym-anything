#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Script Data
echo "Querying script configuration..."
SCRIPT_DATA=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT script_id, script_name, active, script_text FROM vicidial_scripts WHERE script_id='ORDERFLOW';" 2>/dev/null || true)

SCRIPT_EXISTS="false"
SCRIPT_TEXT=""
SCRIPT_ACTIVE=""

if [ -n "$SCRIPT_DATA" ]; then
    SCRIPT_EXISTS="true"
    # Extract fields (tab separated)
    # script_text can contain HTML/newlines, so we handle it carefully in python verifier or just dump raw
    # For bash export, we'll try to grab the text field specifically
    SCRIPT_TEXT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT script_text FROM vicidial_scripts WHERE script_id='ORDERFLOW';" 2>/dev/null || true)
    SCRIPT_ACTIVE=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT active FROM vicidial_scripts WHERE script_id='ORDERFLOW';" 2>/dev/null || true)
fi

# 2. Query Campaign Data
echo "Querying campaign configuration..."
CAMPAIGN_DATA=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT campaign_script, get_call_launch FROM vicidial_campaigns WHERE campaign_id='SALES_Q1';" 2>/dev/null || true)

CAMPAIGN_SCRIPT=""
GET_CALL_LAUNCH=""

if [ -n "$CAMPAIGN_DATA" ]; then
    CAMPAIGN_SCRIPT=$(echo "$CAMPAIGN_DATA" | awk '{print $1}')
    GET_CALL_LAUNCH=$(echo "$CAMPAIGN_DATA" | awk '{print $2}')
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON Result using Python to handle escaping of HTML script text safely
python3 -c "
import json
import os
import sys

def safe_read(path):
    try:
        if os.path.exists(path):
            with open(path, 'r') as f:
                return f.read().strip()
    except:
        pass
    return ''

script_text = sys.argv[1]
script_active = sys.argv[2]
campaign_script = sys.argv[3]
get_call_launch = sys.argv[4]
task_start = int(sys.argv[5])
task_end = int(sys.argv[6])
script_exists = sys.argv[7] == 'true'

result = {
    'task_start': task_start,
    'task_end': task_end,
    'script_exists': script_exists,
    'script_text': script_text,
    'script_active': script_active,
    'campaign_script': campaign_script,
    'get_call_launch': get_call_launch,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
" "$SCRIPT_TEXT" "$SCRIPT_ACTIVE" "$CAMPAIGN_SCRIPT" "$GET_CALL_LAUNCH" "$TASK_START" "$TASK_END" "$SCRIPT_EXISTS"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="