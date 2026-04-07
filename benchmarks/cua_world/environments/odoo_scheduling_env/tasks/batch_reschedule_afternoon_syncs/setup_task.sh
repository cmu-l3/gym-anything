#!/bin/bash
echo "=== Setting up batch_reschedule_afternoon_syncs task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is logged in
ensure_odoo_logged_in

# Reset target events to known "bad" state (Afternoon)
# "Operations Daily Sync" -> 14:00
# "Sales Pipeline Sync" -> 15:00
python3 << 'PYTHON_EOF'
import xmlrpc.client
import datetime
import json

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

def get_date_str(base_date, hour, minute):
    return base_date.replace(hour=hour, minute=minute, second=0).strftime('%Y-%m-%d %H:%M:%S')

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Baseline dictionary to store initial state
    baseline = {}

    # 1. Reset "Operations Daily Sync" (Target 1)
    # Should be tomorrow (ev_soon(1)) at 14:00
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Operations Daily Sync']]],
        {'fields': ['id', 'start', 'stop', 'duration']})
    
    if events:
        evt = events[0]
        # Calculate target date: keep existing date, force 14:00
        current_start = datetime.datetime.strptime(evt['start'], '%Y-%m-%d %H:%M:%S')
        new_start = current_start.replace(hour=14, minute=0, second=0)
        new_stop = new_start + datetime.timedelta(hours=evt['duration']) # Preserve duration
        
        models.execute_kw(db, uid, password, 'calendar.event', 'write',
            [[evt['id']], {
                'start': new_start.strftime('%Y-%m-%d %H:%M:%S'),
                'stop': new_stop.strftime('%Y-%m-%d %H:%M:%S')
            }])
        print(f"Reset 'Operations Daily Sync' to 14:00")
        baseline['Operations Daily Sync'] = {
            'id': evt['id'],
            'initial_start': new_start.strftime('%Y-%m-%d %H:%M:%S'),
            'duration': evt['duration']
        }

    # 2. Reset "Sales Pipeline Sync" (Target 2)
    # Should be next Friday (ev(4)) at 15:00
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Sales Pipeline Sync']]],
        {'fields': ['id', 'start', 'stop', 'duration']})
        
    if events:
        evt = events[0]
        current_start = datetime.datetime.strptime(evt['start'], '%Y-%m-%d %H:%M:%S')
        new_start = current_start.replace(hour=15, minute=0, second=0)
        new_stop = new_start + datetime.timedelta(hours=evt['duration'])
        
        models.execute_kw(db, uid, password, 'calendar.event', 'write',
            [[evt['id']], {
                'start': new_start.strftime('%Y-%m-%d %H:%M:%S'),
                'stop': new_stop.strftime('%Y-%m-%d %H:%M:%S')
            }])
        print(f"Reset 'Sales Pipeline Sync' to 15:00")
        baseline['Sales Pipeline Sync'] = {
            'id': evt['id'],
            'initial_start': new_start.strftime('%Y-%m-%d %H:%M:%S'),
            'duration': evt['duration']
        }

    # 3. Record "Weekly Team Kickoff" (Control)
    # Should be 09:00, verify it
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Weekly Team Kickoff']]],
        {'fields': ['id', 'start', 'duration']})
    if events:
        baseline['Weekly Team Kickoff'] = {
            'id': events[0]['id'],
            'initial_start': events[0]['start']
        }

    # Save baseline to file
    with open('/tmp/task_baseline.json', 'w') as f:
        json.dump(baseline, f)

except Exception as e:
    print(f"Setup Error: {e}")
PYTHON_EOF

# Navigate to Calendar (Week view to see context)
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=week"

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="