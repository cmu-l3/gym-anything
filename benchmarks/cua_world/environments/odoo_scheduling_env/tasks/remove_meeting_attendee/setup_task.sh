#!/bin/bash
set -e
echo "=== Setting up remove_meeting_attendee task ==="

# Source utilities (do NOT use set -e before sourcing)
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Reset/Ensure the "Budget Committee Meeting" has the correct initial attendees
# This ensures the task is deterministic even if retried
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Find the event
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Budget Committee Meeting']]],
        {'fields': ['id', 'name', 'partner_ids'], 'limit': 1})

    if not events:
        print("ERROR: 'Budget Committee Meeting' not found. Creating it...", file=sys.stderr)
        # Fallback creation logic if event missing (resilience)
        # Note: In a real run, setup_data.py creates this, but we handle the edge case
        partners_to_find = ["Grace Patel", "Henry Kim", "Bob Williams", "James O'Brien"]
        pids = []
        for name in partners_to_find:
            res = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', name]]])
            if res: pids.append(res[0])
        
        vals = {
            'name': 'Budget Committee Meeting',
            'location': 'Board Room',
            'description': 'Monthly budget review and department budget approvals.',
            'partner_ids': [[6, 0, pids]],
            'start': '2023-01-01 10:00:00', # Dates are illustrative, Odoo handles rolling
            'stop': '2023-01-01 11:30:00',
        }
        eid = models.execute_kw(db, uid, password, 'calendar.event', 'create', [vals])
        print(f"Created event {eid}")
        events = [{'id': eid}]

    event_id = events[0]['id']

    # 2. Ensure exact attendee list matches task start requirements
    # We need: Grace Patel, Henry Kim, Bob Williams, James O'Brien
    target_attendees = ["Grace Patel", "Henry Kim", "Bob Williams", "James O'Brien"]
    partner_ids = []
    
    for name in target_attendees:
        p_search = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', name]]])
        if p_search:
            partner_ids.append(p_search[0])
        else:
            print(f"WARNING: Partner {name} not found!", file=sys.stderr)

    # Update the event to have EXACTLY these attendees
    models.execute_kw(db, uid, password, 'calendar.event', 'write',
        [[event_id], {'partner_ids': [[6, 0, partner_ids]]}])
    
    print(f"Event {event_id} reset with {len(partner_ids)} attendees.")

    # 3. Save baseline for verification
    baseline = {
        'event_id': event_id,
        'initial_attendee_count': len(partner_ids),
        'initial_partner_ids': partner_ids
    }
    import json
    with open('/tmp/task_baseline.json', 'w') as f:
        json.dump(baseline, f)

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Calendar
# ensure_firefox handles logic to avoid snap locks and maximize window
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=calendar"

# Wait a moment for UI to settle
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="