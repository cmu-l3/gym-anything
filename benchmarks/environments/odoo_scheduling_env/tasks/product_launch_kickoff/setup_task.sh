#!/bin/bash
echo "=== Setting up product_launch_kickoff task ==="

source /workspace/scripts/task_utils.sh

# Remove any pre-existing 'Product Launch Kickoff' events (clean slate for creation)
# Also ensure 'Sprint Planning - Engineering' exists (it is in base data, but recreate if missing)
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
from datetime import datetime, timedelta

url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Remove any existing Product Launch Kickoff events
    existing = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                 [[['name', 'ilike', 'Product Launch Kickoff']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [existing])
        print(f"Removed {len(existing)} existing 'Product Launch Kickoff' event(s)")

    # Ensure 'Sprint Planning - Engineering' exists as a target for deletion
    sprint = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                               [[['name', '=', 'Sprint Planning - Engineering']]])

    if not sprint:
        # Recreate it 15 days from today at 10 AM
        now = datetime.now()
        days_to_monday = (7 - now.weekday()) % 7 or 7
        next_monday = now + timedelta(days=days_to_monday)
        sprint_start = (next_monday + timedelta(days=15)).replace(
            hour=10, minute=0, second=0, microsecond=0)
        sprint_stop = sprint_start + timedelta(hours=2)

        # Get David Chen and Emma Thompson partner IDs
        partner_names = ['David Chen', 'Emma Thompson', 'Luis Fernandez']
        partner_ids = []
        for name in partner_names:
            pids = models.execute_kw(db, uid, 'admin', 'res.partner', 'search',
                                     [[['name', '=', name]]])
            if pids:
                partner_ids.append((4, pids[0]))

        event_data = {
            'name': 'Sprint Planning - Engineering',
            'start': sprint_start.strftime('%Y-%m-%d %H:%M:%S'),
            'stop': sprint_stop.strftime('%Y-%m-%d %H:%M:%S'),
            'location': 'Engineering Lab',
            'description': 'Plan next 2-week engineering sprint: story points and assignments.',
        }
        if partner_ids:
            event_data['partner_ids'] = partner_ids

        eid = models.execute_kw(db, uid, 'admin', 'calendar.event', 'create', [event_data])
        print(f"Recreated 'Sprint Planning - Engineering' (id={eid})")
    else:
        print(f"'Sprint Planning - Engineering' already exists (id={sprint[0]})")

except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Record baseline AFTER cleanup so counts reflect clean starting state (Anti-pattern 3)
record_task_baseline "product_launch_kickoff"

# Navigate to the calendar so the agent can start working
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
sleep 3

take_screenshot /tmp/product_launch_start.png

echo "Task start state: Odoo Calendar is open."
echo "Agent must: create 'Product Launch Kickoff' with engineering+marketing, Engineering Lab location, agenda, AND delete 'Sprint Planning - Engineering'."
echo "=== product_launch_kickoff task setup complete ==="
