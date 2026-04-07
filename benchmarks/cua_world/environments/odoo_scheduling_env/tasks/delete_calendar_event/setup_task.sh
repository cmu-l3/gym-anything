#!/bin/bash
# Setup for delete_calendar_event task
source /workspace/scripts/task_utils.sh

echo "=== Setting up delete_calendar_event task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ensure firefox is running first to avoid startup delays affecting the user
ensure_firefox "about:blank"

# Record baseline: total event count and target event existence
# We also recreate the event if it's missing (to ensure task is always playable)
python3 << 'PYEOF'
import xmlrpc.client, json, sys, datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
target_name = 'Sales Pipeline Sync'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for target
    targets = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_read',
        [[['name', '=', target_name]]],
        {'fields': ['id', 'name', 'start', 'stop', 'location']})
    
    # If not found, create it (recovery mechanism)
    if not targets:
        print(f"Target '{target_name}' not found, recreating...", file=sys.stderr)
        # Calculate next Friday 15:00
        today = datetime.datetime.now()
        days_ahead = (4 - today.weekday() + 7) % 7
        if days_ahead == 0: days_ahead = 7
        next_friday = today + datetime.timedelta(days=days_ahead)
        start_dt = next_friday.replace(hour=15, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')
        stop_dt = next_friday.replace(hour=16, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')
        
        # Get partner IDs
        p_ids = []
        for name in ['Carol Martinez', 'Bob Williams', 'Isabel Santos']:
            res = models.execute_kw(db, uid, 'admin', 'res.partner', 'search', [[['name', '=', name]]])
            if res: p_ids.append(res[0])

        new_id = models.execute_kw(db, uid, 'admin', 'calendar.event', 'create', [{
            'name': target_name,
            'start': start_dt,
            'stop': stop_dt,
            'location': 'Sales Room',
            'partner_ids': [[6, 0, p_ids]],
            'description': 'Weekly pipeline sync and forecasting.'
        }])
        targets = [{'id': new_id, 'name': target_name}]
        print(f"Created recovery event ID: {new_id}")

    # Count all events
    total_count = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_count', [[]])

    baseline = {
        'total_event_count': total_count,
        'target_event_exists': True,
        'target_event_id': targets[0]['id'],
        'target_event_name': targets[0]['name']
    }

    with open('/tmp/delete_event_baseline.json', 'w') as f:
        json.dump(baseline, f, indent=2)
        
    print(f"Baseline recorded: {total_count} events, target ID: {targets[0]['id']}")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Navigate to Calendar Week View
# We assume the event is in the upcoming week, so Week view is appropriate
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=week"

# Wait for load
sleep 5

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== delete_calendar_event setup complete ==="