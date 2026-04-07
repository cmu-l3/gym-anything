#!/bin/bash
set -e
echo "=== Setting up batch_update_event_location task ==="

# Source utilities (do NOT use set -e before sourcing)
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset specific events to ensure deterministic starting state
# We ensure exactly two events have "Board Room" and record the baseline
python3 << 'PYEOF'
import xmlrpc.client, json, sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Target events to force to "Board Room"
    targets = ["Investor Update Preparation", "Budget Committee Meeting"]
    
    # 1. Reset targets to "Board Room"
    for name in targets:
        ids = models.execute_kw(db, uid, password, 'calendar.event', 'search', [[['name', '=', name]]])
        if ids:
            models.execute_kw(db, uid, password, 'calendar.event', 'write', [ids, {'location': 'Board Room'}])
            print(f"Reset '{name}' (ids={ids}) to 'Board Room'")
        else:
            print(f"ERROR: Target event '{name}' not found!", file=sys.stderr)
            sys.exit(1)

    # 2. Ensure NO OTHER events have "Board Room" (to avoid ambiguity)
    # Search for Board Room events that are NOT in our target list
    others = models.execute_kw(db, uid, password, 'calendar.event', 'search', 
        [[['location', '=', 'Board Room'], ['name', 'not in', targets]]])
    
    if others:
        print(f"Clearing 'Board Room' location from {len(others)} other events...")
        models.execute_kw(db, uid, password, 'calendar.event', 'write', [others, {'location': False}])

    # 3. Record Baseline
    total_count = models.execute_kw(db, uid, password, 'calendar.event', 'search_count', [[]])
    
    board_room_events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['location', '=', 'Board Room']]],
        {'fields': ['id', 'name', 'location', 'start', 'stop', 'partner_ids']})
    
    # Snapshot of ALL events to detect collateral damage later
    all_events_snapshot = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[]],
        {'fields': ['id', 'name', 'location']})

    baseline = {
        'total_event_count': total_count,
        'board_room_events': board_room_events,
        'board_room_ids': [e['id'] for e in board_room_events],
        'all_events_snapshot': {e['id']: e for e in all_events_snapshot}
    }

    with open('/tmp/batch_location_baseline.json', 'w') as f:
        json.dump(baseline, f, indent=2, default=str)
    
    print(f"Baseline recorded: {len(board_room_events)} Board Room events, {total_count} total.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is running and logged in, starting at Calendar list view
# List view is better for finding multiple events
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=list"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="