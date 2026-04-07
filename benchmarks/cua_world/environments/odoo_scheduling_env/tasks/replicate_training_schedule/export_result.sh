#!/bin/bash
echo "=== Exporting replicate_training_schedule results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get the target dates generated in setup
if [ -f /tmp/target_dates.txt ]; then
    IFS=',' read -r TARGET_MONDAY TARGET_TUESDAY < /tmp/target_dates.txt
else
    # Fallback if file missing (shouldn't happen)
    TARGET_MONDAY=$(date -d "next monday + 14 days" +%Y-%m-%d)
    TARGET_TUESDAY=$(date -d "next monday + 15 days" +%Y-%m-%d)
fi

echo "Checking events for Monday: $TARGET_MONDAY and Tuesday: $TARGET_TUESDAY"

# Query Odoo for all "Security Workshop" events and export to JSON
python3 << PYTHON_EOF
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

    # Search for all events containing "Security Workshop"
    domain = [['name', 'ilike', 'Security Workshop']]
    fields = ['id', 'name', 'start', 'stop', 'location', 'description', 'recurrency', 'create_date']
    
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read', [domain], {'fields': fields})

    # Get task start time for anti-gaming check
    task_start_ts = 0
    if os.path.exists('/tmp/task_start_time.txt'):
        with open('/tmp/task_start_time.txt', 'r') as f:
            try:
                task_start_ts = float(f.read().strip())
            except:
                pass

    result_data = {
        "target_monday": "$TARGET_MONDAY",
        "target_tuesday": "$TARGET_TUESDAY",
        "task_start_ts": task_start_ts,
        "events": events
    }

    with open(output_file, 'w') as f:
        json.dump(result_data, f, indent=2)

    print(f"Exported {len(events)} events to {output_file}")

except Exception as e:
    print(f"Error exporting results: {e}", file=sys.stderr)
    # Create empty result to avoid file-not-found errors in verifier
    with open(output_file, 'w') as f:
        json.dump({"error": str(e), "events": []}, f)
PYTHON_EOF

# Set permissions so verifier can read it
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="