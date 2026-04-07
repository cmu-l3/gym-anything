#!/bin/bash
echo "=== Exporting schedule_new_hire_onboarding results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract events from Odoo database via XML-RPC
# We look for events created after TASK_START containing "Sarah Connor"
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import time
from datetime import datetime, timedelta

url = "http://localhost:8069"
db = "odoo_scheduling"
username = "admin"
password = "admin"
task_start_ts = $TASK_START

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Calculate target date (Friday of next week) to verify date correctness
    today = datetime.now().date()
    days_until_monday = (7 - today.weekday()) % 7 or 7
    next_monday = today + timedelta(days=days_until_monday)
    target_friday = next_monday + timedelta(days=4)
    target_date_str = target_friday.strftime('%Y-%m-%d')

    # Search for events created after task start
    # Note: Odoo stores create_date in UTC. 
    # We'll filter loosely by name first, then validate details.
    domain = [
        ['name', 'ilike', 'Sarah Connor']
    ]
    
    fields = ['name', 'start', 'stop', 'location', 'partner_ids', 'create_date']
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read', [domain], {'fields': fields})

    # Fetch partner names for verification
    partner_map = {}
    if events:
        all_partner_ids = set()
        for e in events:
            all_partner_ids.update(e['partner_ids'])
        
        if all_partner_ids:
            partners = models.execute_kw(db, uid, password, 'res.partner', 'read', [list(all_partner_ids)], {'fields': ['name']})
            for p in partners:
                partner_map[p['id']] = p['name']

    # Filter events created during the task window
    # Odoo create_date is string "YYYY-MM-DD HH:MM:SS"
    valid_events = []
    for e in events:
        c_date = datetime.strptime(e['create_date'], "%Y-%m-%d %H:%M:%S")
        # Simple check: if create_date is recent (after task start)
        # converting task_start_ts to datetime
        start_dt = datetime.fromtimestamp(task_start_ts)
        # Allow some buffer for clock skew if needed, but usually docker time is consistent
        if c_date >= start_dt:
            # Augment with partner names
            attendee_names = [partner_map.get(pid, "Unknown") for pid in e['partner_ids']]
            e['attendee_names'] = attendee_names
            valid_events.append(e)

    result = {
        "task_start": task_start_ts,
        "target_date_str": target_date_str,
        "found_events": valid_events,
        "event_count": len(valid_events)
    }

    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f, indent=2)

except Exception as e:
    print(f"Error exporting results: {e}", file=sys.stderr)
    # Create empty result file on failure to avoid copier errors
    with open("/tmp/task_result.json", "w") as f:
        json.dump({"error": str(e), "found_events": []}, f)

PYTHON_EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="