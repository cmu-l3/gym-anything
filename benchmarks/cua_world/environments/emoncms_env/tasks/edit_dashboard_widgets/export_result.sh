#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Get Current Dashboard Content
DASH_NAME="Server Room Overview"
# We fetch the raw content JSON string from the DB
CURRENT_CONTENT=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -B -e "SELECT content FROM dashboard WHERE name='$DASH_NAME' LIMIT 1" 2>/dev/null)

# 4. Get Correct Feed IDs (Ground Truth)
# We need to know what the 'server_*' feed IDs are to check if the user assigned them correctly.
SERVER_POWER_ID=$(db_query "SELECT id FROM feeds WHERE name='server_power' AND tag='server_room'" 2>/dev/null)
SERVER_TEMP_ID=$(db_query "SELECT id FROM feeds WHERE name='server_temp' AND tag='server_room'" 2>/dev/null)
SERVER_HUMIDITY_ID=$(db_query "SELECT id FROM feeds WHERE name='server_humidity' AND tag='server_room'" 2>/dev/null)

# 5. Determine if App was Running (Firefox)
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 6. Create Result JSON
# We embed the dashboard content JSON directly so the python verifier can parse it safely
# We handle the potential emptiness of variables

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use python to construct JSON to handle escaping of nested JSON strings properly
python3 -c "
import json
import sys

try:
    content_str = sys.argv[1]
    content_json = json.loads(content_str) if content_str else []
except:
    content_json = []

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'app_running': $APP_RUNNING,
    'dashboard_found': bool(sys.argv[1]),
    'dashboard_content': content_json,
    'ground_truth': {
        'server_power_id': '${SERVER_POWER_ID}',
        'server_temp_id': '${SERVER_TEMP_ID}',
        'server_humidity_id': '${SERVER_HUMIDITY_ID}'
    }
}
print(json.dumps(result))
" "$CURRENT_CONTENT" > "$TEMP_JSON"

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="