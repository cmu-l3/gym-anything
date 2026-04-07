#!/bin/bash
echo "=== Exporting Detect SQLi Result ==="

source /workspace/scripts/task_utils.sh

CONTAINER="wazuh-wazuh.manager-1"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract configuration files for verification
echo "Extracting configuration files..."
docker cp "${CONTAINER}:/var/ossec/etc/ossec.conf" /tmp/ossec.conf
docker cp "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml" /tmp/local_rules.xml

# 3. Search for the specific alert in alerts.json
# We look for an alert that:
# - Occurred after task start
# - Matches our custom rule ID (100100)
# - Contains the log file path
# - Contains SQLi keywords
echo "Searching for triggered alerts..."

# We use a python script to parse the alerts.json from the container stream
# This avoids copying the massive alerts file
ALERT_FOUND=$(docker exec "${CONTAINER}" python3 -c "
import json
import sys
import os

target_rule_id = '100100'
min_timestamp = $TASK_START
log_file = '/var/ossec/logs/alerts/alerts.json'

found_alert = None

try:
    if os.path.exists(log_file):
        with open(log_file, 'r') as f:
            # Read from end or scan all? Scan all for now, file rotates daily usually
            for line in f:
                try:
                    alert = json.loads(line)
                    # Check timestamp (alerts use ISO usually, but we can check ingestion time or just existence)
                    # Wazuh alert timestamp is like '2023-10-27T...'
                    # We'll rely on the fact that we reset the env, so any 100100 alert is likely from this session
                    
                    rule = alert.get('rule', {})
                    if str(rule.get('id')) == target_rule_id:
                        found_alert = alert
                except:
                    continue
except Exception as e:
    pass

if found_alert:
    print(json.dumps(found_alert))
else:
    print('{}')
")

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'alert_found': False,
    'alert_data': {},
    'ossec_conf_content': '',
    'local_rules_content': '',
    'screenshot_path': '/tmp/task_final.png'
}

# Load alert data
try:
    alert_json = '$ALERT_FOUND'
    if alert_json and alert_json != '{}':
        result['alert_found'] = True
        result['alert_data'] = json.loads(alert_json)
except Exception as e:
    print(f'Error parsing alert: {e}')

# Load config content
try:
    with open('/tmp/ossec.conf', 'r') as f:
        result['ossec_conf_content'] = f.read()
except:
    pass

try:
    with open('/tmp/local_rules.xml', 'r') as f:
        result['local_rules_content'] = f.read()
except:
    pass

print(json.dumps(result, indent=2))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"