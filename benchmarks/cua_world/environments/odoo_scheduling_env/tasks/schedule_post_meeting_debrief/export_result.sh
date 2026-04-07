#!/bin/bash
echo "=== Exporting schedule_post_meeting_debrief results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Export event data to JSON
# We need the times of BOTH the reference event and the created event
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Fetch reference event
    ref_events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
                                  [[['name', '=', 'Investor Update Preparation']]],
                                  {'fields': ['name', 'start', 'stop', 'duration'], 'limit': 1})
    
    # Fetch target event (Debrief)
    target_events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
                                     [[['name', '=', 'Debrief']]],
                                     {'fields': ['name', 'start', 'stop', 'duration', 'write_date']})

    result = {
        "reference_event": ref_events[0] if ref_events else None,
        "target_events": target_events,
        "task_start_ts": int(os.environ.get('TASK_START', 0)),
        "task_end_ts": int(os.environ.get('TASK_END', 0))
    }

    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)
        
    print(f"Exported data for {len(target_events)} target events.")

except Exception as e:
    print(f"Export failed: {e}", file=sys.stderr)
    # Write a failure result
    with open(output_file, 'w') as f:
        json.dump({"error": str(e)}, f)
PYTHON_EOF

# Handle permissions for the exported file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="