#!/bin/bash
set -e
echo "=== Setting up batch_add_attendee task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Calculate the target week dates (Next Monday to Friday) to display to the agent
# Matches the logic in setup_data.py
DATES_JSON=$(python3 << 'EOF'
import json
from datetime import datetime, timedelta

now = datetime.now().replace(second=0, microsecond=0)
days_to_monday = (7 - now.weekday()) % 7 or 7
next_monday = now + timedelta(days=days_to_monday)
next_friday = next_monday + timedelta(days=4)

print(json.dumps({
    "monday_str": next_monday.strftime('%Y-%m-%d'),
    "friday_str": next_friday.strftime('%Y-%m-%d'),
    "monday_display": next_monday.strftime('%A, %B %d'),
    "friday_display": next_friday.strftime('%A, %B %d')
}))
EOF
)

START_DATE=$(echo "$DATES_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['monday_str'])")
END_DATE=$(echo "$DATES_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['friday_str'])")
DISPLAY_START=$(echo "$DATES_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['monday_display'])")
DISPLAY_END=$(echo "$DATES_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['friday_display'])")

echo "Target Week: $DISPLAY_START to $DISPLAY_END"
echo "$START_DATE" > /tmp/target_start_date.txt
echo "$END_DATE" > /tmp/target_end_date.txt

# 3. Ensure Firefox is running and at the Calendar view
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# 4. Clean up any previous run artifacts (idempotency)
# Ensure James O'Brien is NOT on Alice's meetings for next week yet
python3 << EOF
import xmlrpc.client
url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find James and Alice IDs
    partners = models.execute_kw(db, uid, password, 'res.partner', 'search_read', 
        [[['name', 'in', ['Alice Johnson', "James O'Brien"]]]], 
        {'fields': ['id', 'name']})
    
    alice_id = next((p['id'] for p in partners if p['name'] == 'Alice Johnson'), None)
    james_id = next((p['id'] for p in partners if p['name'] == "James O'Brien"), None)

    if alice_id and james_id:
        # Find events in target week involving Alice
        domain = [
            ['start', '>=', '$START_DATE 00:00:00'],
            ['stop', '<=', '$END_DATE 23:59:59'],
            ['partner_ids', 'in', [alice_id]]
        ]
        event_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search', [domain])
        
        # Remove James from these events if present (reset state)
        for event in models.execute_kw(db, uid, password, 'calendar.event', 'read', [event_ids, ['partner_ids']]):
            if james_id in event['partner_ids']:
                models.execute_kw(db, uid, password, 'calendar.event', 'write', 
                    [[event['id']], {'partner_ids': [[3, james_id, 0]]}])
                print(f"Reset event {event['id']}: removed James O'Brien")
except Exception as e:
    print(f"Setup warning: {e}")
EOF

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "INSTRUCTIONS: Add 'James O'Brien' to all meetings attended by 'Alice Johnson' between $DISPLAY_START and $DISPLAY_END."