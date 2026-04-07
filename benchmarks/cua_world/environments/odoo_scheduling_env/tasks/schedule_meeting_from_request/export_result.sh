#!/bin/bash
echo "=== Exporting schedule_meeting_from_request result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Path to the expected values generated in setup
EXPECTED_FILE="/tmp/task_expected_values.json"

# Python script to query Odoo and compare with expectations
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import os
from datetime import datetime

url = "http://localhost:8069"
db = "odoo_scheduling"
username = "admin"
password = "admin"
output_file = "/tmp/task_result.json"
expected_file = "/tmp/task_expected_values.json"

result = {
    "event_found": False,
    "event_details": {},
    "expected_details": {},
    "matches": {}
}

try:
    # Load expected values
    if os.path.exists(expected_file):
        with open(expected_file, 'r') as f:
            expected = json.load(f)
            result["expected_details"] = expected
    else:
        # Fallback if file missing (should not happen)
        expected = {"subject": "Systems Infrastructure Check"}

    # Authenticate with Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for the event
    # We filter by name exactly as requested
    event_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', '=', expected['subject']]]])
    
    # If multiple found (e.g. from previous runs), take the most recently created one
    if event_ids:
        events = models.execute_kw(db, uid, password, 'calendar.event', 'read',
            [event_ids], 
            {'fields': ['name', 'start', 'stop', 'duration', 'location', 'partner_ids', 'create_date']})
        
        # Sort by create_date descending
        events.sort(key=lambda x: x['create_date'], reverse=True)
        event = events[0]
        
        result["event_found"] = True
        
        # Resolve partner IDs to names
        partner_ids = event.get('partner_ids', [])
        partner_names = []
        if partner_ids:
            partners = models.execute_kw(db, uid, password, 'res.partner', 'read',
                [partner_ids], {'fields': ['name']})
            partner_names = [p['name'] for p in partners]
        
        # Populate actual details
        result["event_details"] = {
            "name": event.get('name'),
            "start": event.get('start'),       # "YYYY-MM-DD HH:MM:SS"
            "stop": event.get('stop'),
            "duration": event.get('duration'), # Float hours
            "location": event.get('location'),
            "attendees": partner_names
        }

except Exception as e:
    result["error"] = str(e)
    print(f"Error exporting results: {e}", file=sys.stderr)

# Write result to file
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result saved to {output_file}")
PYTHON_EOF

# Set permissions so host can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="