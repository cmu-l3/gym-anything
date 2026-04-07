#!/bin/bash
echo "=== Exporting reschedule_to_first_open_slot result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the final state of the target event using Python
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import os
import sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find the target event
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Strategic Partnership Review']]],
        {'fields': ['name', 'start', 'stop', 'duration', 'write_date']}
    )
    
    target_event = events[0] if events else None
    
    # Get expected solution from setup file
    expected_start = ""
    if os.path.exists('/tmp/expected_solution.txt'):
        with open('/tmp/expected_solution.txt', 'r') as f:
            expected_start = f.read().strip()

    # Read timestamps
    task_start = 0
    if os.path.exists('/tmp/task_start_time.txt'):
        with open('/tmp/task_start_time.txt', 'r') as f:
            try:
                task_start = int(f.read().strip())
            except: pass

    # Construct result object
    result = {
        "event_found": bool(target_event),
        "event_data": target_event,
        "expected_start_str": expected_start,
        "task_start_ts": task_start,
        "screenshot_path": "/tmp/task_final.png"
    }

    # Write to JSON
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)

    print(json.dumps(result, indent=2))

except Exception as e:
    print(f"Export failed: {e}", file=sys.stderr)
    # Write failure json
    with open(output_file, 'w') as f:
        json.dump({"error": str(e)}, f)
PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="