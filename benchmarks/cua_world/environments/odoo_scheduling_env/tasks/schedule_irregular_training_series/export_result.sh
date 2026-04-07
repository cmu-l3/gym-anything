#!/bin/bash
echo "=== Exporting schedule_irregular_training_series result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the schedule file was accessed
# We check the access time (atime) of the text file
SCHEDULE_FILE="/home/ga/Documents/leadership_schedule.txt"
FILE_ACCESSED="false"
if [ -f "$SCHEDULE_FILE" ]; then
    ATIME=$(stat -c %X "$SCHEDULE_FILE" 2>/dev/null || echo "0")
    if [ "$ATIME" -gt "$TASK_START" ]; then
        FILE_ACCESSED="true"
    fi
fi

# 2. Query Odoo for the created events
# We look for events named "Leadership 101" created after task start
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import datetime
import os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
task_start = float(os.popen("cat /tmp/task_start_time.txt").read().strip() or 0)

result_data = {
    "file_accessed": os.environ.get("FILE_ACCESSED") == "true",
    "events_found": [],
    "ground_truth": [],
    "screenshot_path": "/tmp/task_final.png"
}

try:
    # Load ground truth
    if os.path.exists("/tmp/ground_truth_schedule.json"):
        with open("/tmp/ground_truth_schedule.json", "r") as f:
            result_data["ground_truth"] = json.load(f)

    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for events
    # We fetch name, start, stop, location, description, partner_ids, recurrency
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', 'ilike', 'Leadership 101']]], 
        {'fields': ['name', 'start', 'stop', 'location', 'description', 'partner_ids', 'recurrency', 'create_date']}
    )

    # Filter for events created during the task
    # Note: Odoo create_date is string UTC. We'll capture all and let verifier filter/match.
    # But ideally we verify they are new.
    
    # Get Attendee Names for verification
    for event in events:
        # Resolve partner IDs to names
        partner_ids = event.get('partner_ids', [])
        attendees = []
        if partner_ids:
            partners = models.execute_kw(db, uid, password, 'res.partner', 'read', [partner_ids], {'fields': ['name']})
            attendees = [p['name'] for p in partners]
        
        event['attendee_names'] = attendees
        result_data["events_found"].append(event)

except Exception as e:
    result_data["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result_data, f, default=str)

PYTHON_EOF

# Take final screenshot
take_screenshot /tmp/task_final.png

# Move result to allow reading by verifier (chmod)
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="