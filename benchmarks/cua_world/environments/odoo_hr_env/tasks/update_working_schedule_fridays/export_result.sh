#!/bin/bash
echo "=== Exporting update_working_schedule_fridays result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------------------
# Extract Calendar Data via XML-RPC
# ---------------------------------------------------------------------------
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result_data = {
    "calendar_found": False,
    "attendances": [],
    "write_date": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Fetch the calendar
    # We fetch fields: attendance_ids and write_date
    calendars = models.execute_kw(db, uid, password, 'resource.calendar', 'search_read', 
        [[['name', '=', 'Standard 40 hours/week']]], 
        {'fields': ['attendance_ids', 'write_date'], 'limit': 1}
    )
    
    if calendars:
        cal = calendars[0]
        result_data["calendar_found"] = True
        result_data["write_date"] = cal.get('write_date')
        
        attendance_ids = cal.get('attendance_ids', [])
        
        if attendance_ids:
            # Read the attendance lines
            attendances = models.execute_kw(db, uid, password, 'resource.calendar.attendance', 'read',
                [attendance_ids],
                {'fields': ['dayofweek', 'hour_from', 'hour_to', 'day_period', 'name']}
            )
            result_data["attendances"] = attendances

except Exception as e:
    result_data["error"] = str(e)

# Save result to file
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result_data, f, indent=2)

PYEOF

# Move result to accessible location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/task_result_temp.json

# Check if app is running (Firefox)
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="