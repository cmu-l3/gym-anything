#!/bin/bash
echo "=== Exporting batch_reschedule_afternoon_syncs results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture final database state using Python
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import os
import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Load baseline
    baseline = {}
    if os.path.exists('/tmp/task_baseline.json'):
        with open('/tmp/task_baseline.json', 'r') as f:
            baseline = json.load(f)

    # 1. Fetch Target Events
    targets = ['Operations Daily Sync', 'Sales Pipeline Sync']
    results = {}
    
    for name in targets:
        # Search by ID if available in baseline to ensure we get the exact same object
        domain = [['name', '=', name]]
        if name in baseline:
            domain = [['id', '=', baseline[name]['id']]]
            
        events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
            [domain],
            {'fields': ['name', 'start', 'stop', 'duration', 'write_date']})
            
        if events:
            results[name] = events[0]

    # 2. Fetch Control Event
    control_name = 'Weekly Team Kickoff'
    control_domain = [['name', '=', control_name]]
    if control_name in baseline:
        control_domain = [['id', '=', baseline[control_name]['id']]]
        
    control_events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [control_domain],
        {'fields': ['name', 'start', 'duration', 'write_date']})
    
    if control_events:
        results[control_name] = control_events[0]

    # Add task start time
    task_start = 0
    if os.path.exists('/tmp/task_start_time.txt'):
        with open('/tmp/task_start_time.txt', 'r') as f:
            task_start = float(f.read().strip())

    output = {
        'baseline': baseline,
        'final_state': results,
        'task_start_time': task_start
    }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(output, f)
    
    print("Exported result JSON.")

except Exception as e:
    print(f"Export Error: {e}")
    # Write empty result on error to avoid crash
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="