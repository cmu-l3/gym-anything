#!/bin/bash
echo "=== Exporting update_recurring_event_series result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo database for the state of the events
# We look for the events and check if the location updated for future instances
python3 << 'PYEOF'
import xmlrpc.client
import sys
import json
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
password = 'admin'
username = 'admin'

result = {
    "events_found": False,
    "event_count": 0,
    "first_event_location": None,
    "future_event_location": None,
    "is_recurring": False,
    "locations_consistent": False
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for instances of the meeting
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read', 
        [[['name', '=', 'Weekly Operations Sync']]], 
        {'fields': ['name', 'location', 'start', 'recurrency', 'recurrence_id']})

    if events:
        result["events_found"] = True
        result["event_count"] = len(events)
        
        # Sort by start date to distinguish first vs future
        events.sort(key=lambda x: x['start'])
        
        # Check recurrence status (any event in series marked recurring?)
        # In Odoo 17, individual events in a series might mark 'recurrency' differently depending on expansion
        # but usually the series master or the events linked to a recurrence_id indicate it.
        result["is_recurring"] = any(e.get('recurrency') for e in events) or any(e.get('recurrence_id') for e in events)

        # Get first event (next Monday)
        first_event = events[0]
        result["first_event_location"] = first_event.get('location')

        # Get a future event (e.g., 3rd in series)
        if len(events) >= 3:
            future_event = events[2]
            result["future_event_location"] = future_event.get('location')
        elif len(events) > 1:
             future_event = events[-1]
             result["future_event_location"] = future_event.get('location')
        else:
             # Only one event found?
             result["future_event_location"] = first_event.get('location')

        # Check consistency
        locations = [e.get('location') for e in events]
        result["locations_consistent"] = all(loc == locations[0] for loc in locations)

except Exception as e:
    result["error"] = str(e)

# Save to JSON
with open('/tmp/task_result_data.json', 'w') as f:
    json.dump(result, f)
PYEOF

# Create final JSON result
# We wrap the python output into the standard format
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "odoo_data": $(cat /tmp/task_result_data.json 2>/dev/null || echo "{}")
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"
rm -f /tmp/task_result_data.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="