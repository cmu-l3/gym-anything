#!/bin/bash
set -e

echo "=== Exporting bulk_delete_project_meetings result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Run Python script to query final database state and compare with baseline
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import os
import time

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

output_file = '/tmp/task_result.json'
baseline_file = '/tmp/bulk_delete_baseline.json'

result = {
    'task_end_time': int(time.time()),
    'baseline_found': False,
    'auth_success': False,
    'phoenix_remaining': -1,
    'non_phoenix_remaining': -1,
    'total_remaining': -1,
    'deleted_phoenix_count': 0,
    'deleted_non_phoenix_count': 0,
    'state_changed': False
}

try:
    # Load baseline
    if os.path.exists(baseline_file):
        with open(baseline_file, 'r') as f:
            baseline = json.load(f)
        result['baseline_found'] = True
        result['baseline'] = baseline
    else:
        print("ERROR: Baseline file not found", file=sys.stderr)
        # Continue to at least record current state
        baseline = {'total_events': 0, 'phoenix_events': 4, 'non_phoenix_events': 0}

    # Authenticate
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if uid:
        result['auth_success'] = True
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

        # Get current state
        total_now = models.execute_kw(db, uid, password, 'calendar.event', 'search_count', [[]])
        
        # Count remaining Phoenix events
        phoenix_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
            [[['name', 'like', 'Project Phoenix']]])
        phoenix_now = len(phoenix_ids)
        
        non_phoenix_now = total_now - phoenix_now

        # Calculate deltas
        result['phoenix_remaining'] = phoenix_now
        result['non_phoenix_remaining'] = non_phoenix_now
        result['total_remaining'] = total_now
        
        if result['baseline_found']:
            result['deleted_phoenix_count'] = baseline['phoenix_events'] - phoenix_now
            result['deleted_non_phoenix_count'] = baseline['non_phoenix_events'] - non_phoenix_now
            result['state_changed'] = (total_now != baseline['total_events'])
            result['expected_decrease'] = baseline['phoenix_events']

    else:
        print("ERROR: Authentication failed", file=sys.stderr)

except Exception as e:
    result['error'] = str(e)
    print(f"Export Error: {e}", file=sys.stderr)

# Write result
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result exported to {output_file}")
PYTHON_EOF

# Set permissions so the host can read it (if mapped, though copy_from_env handles this)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="