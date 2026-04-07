#!/bin/bash
echo "=== Exporting terminate_recurring_event_series result ==="

source /workspace/scripts/task_utils.sh

# Get target date from setup
TARGET_DATE=$(cat /tmp/target_date.txt)
echo "Verifying against Target Date: $TARGET_DATE"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo database for verification data
# We need to check:
# 1. Are there events AFTER the target date? (Should be 0)
# 2. Is there an event ON the target date? (Should be 1)
# 3. Are there events BEFORE the target date? (Should be > 0, history preserved)
# 4. Did the recurrence rule change?

python3 << PYTHON_EOF
import xmlrpc.client, json, sys
from datetime import datetime, timedelta

url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'
target_date_str = '$TARGET_DATE'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Define date thresholds
    target_dt = datetime.strptime(target_date_str, '%Y-%m-%d')
    day_after = (target_dt + timedelta(days=1)).strftime('%Y-%m-%d 00:00:00')
    day_start = target_dt.strftime('%Y-%m-%d 00:00:00')
    day_end = target_dt.strftime('%Y-%m-%d 23:59:59')
    
    # 1. Count future events (strictly after target day)
    future_count = models.execute_kw(db, uid, password, 'calendar.event', 'search_count',
        [[
            ['name', '=', 'Project Phoenix Standup'],
            ['start', '>', day_end]
        ]])

    # 2. Check existence on target day
    target_day_events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[
            ['name', '=', 'Project Phoenix Standup'],
            ['start', '>=', day_start],
            ['start', '<=', day_end]
        ]],
        {'fields': ['id', 'start', 'recurrency', 'recurrence_id']})
    
    target_exists = len(target_day_events) > 0
    recurrence_id = target_day_events[0]['recurrence_id'][0] if target_exists and target_day_events[0]['recurrence_id'] else None

    # 3. Count past events (before target day)
    past_count = models.execute_kw(db, uid, password, 'calendar.event', 'search_count',
        [[
            ['name', '=', 'Project Phoenix Standup'],
            ['start', '<', day_start]
        ]])

    # 4. Check recurrence rule details if it exists
    recurrence_data = {}
    if recurrence_id:
        rec_info = models.execute_kw(db, uid, password, 'calendar.recurrence', 'read',
            [[recurrence_id], ['end_type', 'until', 'count']])
        if rec_info:
            recurrence_data = rec_info[0]

    result = {
        "target_date": target_date_str,
        "future_event_count": future_count,
        "target_event_exists": target_exists,
        "past_event_count": past_count,
        "recurrence_info": recurrence_data,
        "timestamp": datetime.now().isoformat()
    }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

    print("Exported result:")
    print(json.dumps(result, indent=2))

except Exception as e:
    print(f"Error checking DB: {e}", file=sys.stderr)
    # Write a failure result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)
PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="