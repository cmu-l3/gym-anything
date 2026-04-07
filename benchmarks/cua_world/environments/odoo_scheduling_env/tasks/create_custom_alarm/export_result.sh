#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_custom_alarm results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo database to verify the state
# We need to export this to a JSON file for the verifier to read
python3 << PYEOF
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "event_found": False,
    "alarms_found": [],
    "status": "checked"
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find the event
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Q2 Financial Review']]],
        {'fields': ['alarm_ids']})

    if events:
        result['event_found'] = True
        event = events[0]
        alarm_ids = event.get('alarm_ids', [])
        
        if alarm_ids:
            # Fetch details of the alarms associated with the event
            alarms = models.execute_kw(db, uid, password, 'calendar.alarm', 'read', [alarm_ids])
            for alarm in alarms:
                result['alarms_found'].append({
                    'id': alarm.get('id'),
                    'name': alarm.get('name'),
                    'alarm_type': alarm.get('alarm_type'), # 'email' or 'notification'
                    'duration': alarm.get('duration'),
                    'interval': alarm.get('interval'),     # 'minutes', 'hours', 'days'
                    'create_date': alarm.get('create_date') # For anti-gaming check
                })

except Exception as e:
    result['error'] = str(e)

# Write to temp file first
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Move to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="