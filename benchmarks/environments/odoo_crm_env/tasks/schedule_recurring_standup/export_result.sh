#!/bin/bash
echo "=== Exporting schedule_recurring_standup results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the created event
# We look for events created AFTER the task start time
TASK_START=$(cat /tmp/task_start_iso.txt 2>/dev/null || date -Iseconds)

echo "Querying Odoo for calendar events..."
python3 - <<PYEOF
import xmlrpc.client
import json
import datetime
import sys

# Output file path
OUTPUT_FILE = "/tmp/task_result.json"

result = {
    "event_found": False,
    "events": [],
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = common.authenticate('odoodb', 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

    # Search for the specific event name
    # We don't filter by create_date strictly in the search to debug if it was created at all
    # Verification logic will handle timestamp checks
    event_ids = models.execute_kw('odoodb', uid, 'admin', 'calendar.event', 'search',
        [[['name', '=', 'Weekly Sales Standup']]])

    if event_ids:
        # Read fields
        fields = ['name', 'start', 'stop', 'description', 'recurrency', 'rrule', 'create_date']
        events_data = models.execute_kw('odoodb', uid, 'admin', 'calendar.event', 'read',
            [event_ids], {'fields': fields})
        
        result["event_found"] = True
        result["events"] = events_data
        print(f"Found {len(events_data)} events")
    else:
        print("No events found with name 'Weekly Sales Standup'")

except Exception as e:
    result["error"] = str(e)
    print(f"Error: {e}")

# Save result to JSON
with open(OUTPUT_FILE, 'w') as f:
    json.dump(result, f, indent=2, default=str)

print(f"Result saved to {OUTPUT_FILE}")
PYEOF

# Set permissions so the host can read it via copy_from_env
chmod 644 /tmp/task_result.json 2>/dev/null || true
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="