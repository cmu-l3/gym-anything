#!/bin/bash
set -e

echo "=== Setting up bulk_delete_project_meetings task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create "Project Phoenix" events and record baseline via Python/XML-RPC
# This ensures a known starting state with exactly 4 target events
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
from datetime import datetime, timedelta

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    # Authenticate
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("ERROR: Authentication failed", file=sys.stderr)
        sys.exit(1)

    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Helper to calculate future dates (Next Monday anchor)
    now = datetime.now()
    days_to_monday = (7 - now.weekday()) % 7 or 7
    next_monday = now + timedelta(days=days_to_monday)

    def ev_time(days_offset, hour, minute=0):
        dt = (next_monday + timedelta(days=days_offset)).replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )
        return dt.strftime('%Y-%m-%d %H:%M:%S')

    # 1. Clean up any existing Project Phoenix events (idempotency)
    existing_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', 'like', 'Project Phoenix']]])
    
    if existing_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing Phoenix events")

    # 2. Create the 4 target events
    events_to_create = [
        {
            'name': 'Project Phoenix - Kickoff Meeting',
            'start': ev_time(0, 13), 'stop': ev_time(0, 14, 30), # Mon 1:00 PM
            'location': 'Conference Room B',
            'description': 'Project Phoenix kickoff: scope definition.'
        },
        {
            'name': 'Project Phoenix - Design Review',
            'start': ev_time(2, 10), 'stop': ev_time(2, 11, 30), # Wed 10:00 AM
            'location': 'Engineering Lab',
            'description': 'Review architectural design.'
        },
        {
            'name': 'Project Phoenix - Sprint Planning',
            'start': ev_time(7, 9), 'stop': ev_time(7, 10),      # Next Mon 9:00 AM
            'location': 'Agile Room',
            'description': 'Sprint 1 planning session.'
        },
        {
            'name': 'Project Phoenix - Stakeholder Update',
            'start': ev_time(10, 15), 'stop': ev_time(10, 16),   # Next Thu 3:00 PM
            'location': 'Board Room',
            'description': 'Monthly stakeholder progress update.'
        }
    ]

    created_ids = []
    for evt in events_to_create:
        eid = models.execute_kw(db, uid, password, 'calendar.event', 'create', [evt])
        created_ids.append(eid)
        print(f"Created event: {evt['name']} (ID: {eid})")

    # 3. Record Baseline State
    total_count = models.execute_kw(db, uid, password, 'calendar.event', 'search_count', [[]])
    phoenix_count = len(created_ids) # We know we just created 4
    non_phoenix_count = total_count - phoenix_count

    baseline = {
        'total_events': total_count,
        'phoenix_events': phoenix_count,
        'non_phoenix_events': non_phoenix_count,
        'phoenix_ids': created_ids,
        'timestamp': int(now.timestamp())
    }

    with open('/tmp/bulk_delete_baseline.json', 'w') as f:
        json.dump(baseline, f, indent=2)

    print(f"Baseline recorded: Total={total_count}, Phoenix={phoenix_count}, Other={non_phoenix_count}")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Calendar
# We use list view initially as it might be easier for bulk delete, 
# but the agent can switch views. We'll start in standard Calendar view.
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=calendar"

# Wait for load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="