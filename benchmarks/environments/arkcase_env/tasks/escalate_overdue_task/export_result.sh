#!/bin/bash
# post_task: Export results for verification

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Data via API
# We need the Task ID saved from setup.
TASK_ID=$(cat /tmp/target_task_id.txt 2>/dev/null || echo "")

API_RESULT="{}"
TASK_FOUND="false"

if [ -n "$TASK_ID" ]; then
    echo "Querying API for Task ID: $TASK_ID"
    API_RESPONSE=$(arkcase_api GET "plugin/task/$TASK_ID")
    
    # validate if we got a JSON response
    if echo "$API_RESPONSE" | grep -q "id"; then
        API_RESULT="$API_RESPONSE"
        TASK_FOUND="true"
    fi
else
    echo "No Task ID found from setup. Trying to search by title..."
    # Fallback: search for tasks with the specific title (less reliable but useful backup)
    SEARCH_RESPONSE=$(arkcase_api GET "plugin/task?title=Initial%20Legal%20Review")
    # Assuming search returns list, take first
    API_RESULT=$(echo "$SEARCH_RESPONSE" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps(d[0]) if isinstance(d, list) and len(d)>0 else '{}')" 2>/dev/null)
    if [ "$API_RESULT" != "{}" ]; then
        TASK_FOUND="true"
    fi
fi

# 3. Gather Environment Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")
TOMORROW_DATE=$(date -d "tomorrow" +%Y-%m-%d)
TODAY_DATE=$(date +%Y-%m-%d)

# 4. Save Result JSON
# We embed the raw API result into our wrapper JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys

try:
    api_data = json.loads('''$API_RESULT''')
except:
    api_data = {}

result = {
    'task_found': '$TASK_FOUND' == 'true',
    'api_data': api_data,
    'meta': {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'app_running': '$APP_RUNNING' == 'true',
        'ref_date_tomorrow': '$TOMORROW_DATE',
        'ref_date_today': '$TODAY_DATE'
    }
}
print(json.dumps(result, indent=2))
" > "$TEMP_JSON"

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported to /tmp/task_result.json"
echo "=== Export Complete ==="