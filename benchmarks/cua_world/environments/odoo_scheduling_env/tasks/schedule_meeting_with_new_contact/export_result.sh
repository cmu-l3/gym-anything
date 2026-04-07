#!/bin/bash
echo "=== Exporting schedule_meeting_with_new_contact result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query Odoo state and save to JSON
# This runs inside the container
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'

def serialize(obj):
    if isinstance(obj, (datetime.date, datetime.datetime)):
        return obj.isoformat()
    return str(obj)

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Load baseline
    try:
        with open('/tmp/task_baseline.json', 'r') as f:
            baseline = json.load(f)
    except:
        baseline = {"max_partner_id": 0, "max_event_id": 0}

    result = {
        "baseline": baseline,
        "contact_found": False,
        "event_found": False,
        "contact_data": {},
        "event_data": {},
        "attendee_link_verified": False,
        "timestamp": datetime.datetime.now().isoformat()
    }

    # 1. Search for the Contact
    # We search specifically for the name requested
    contact_ids = models.execute_kw(db, uid, password, 'res.partner', 'search',
                                   [[['name', '=', 'Patricia Nguyen']]])
    
    target_partner_id = None
    
    if contact_ids:
        # Get the most recently created one if multiple
        target_partner_id = max(contact_ids)
        contact_data = models.execute_kw(db, uid, password, 'res.partner', 'read',
                                        [[target_partner_id], 
                                         ['name', 'email', 'phone', 'function', 'parent_id', 'company_name']])
        if contact_data:
            result['contact_found'] = True
            result['contact_data'] = contact_data[0]
            # Check if this is a newly created record
            result['contact_is_new'] = target_partner_id > baseline.get('max_partner_id', 0)

    # 2. Search for the Event
    # Search by title keyword
    event_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                                 [[['name', 'ilike', 'Onboarding Call']]])
    
    if event_ids:
        target_event_id = max(event_ids)
        event_data = models.execute_kw(db, uid, password, 'calendar.event', 'read',
                                      [[target_event_id],
                                       ['name', 'start', 'stop', 'location', 'description', 'partner_ids', 'duration']])
        if event_data:
            result['event_found'] = True
            result['event_data'] = event_data[0]
            result['event_is_new'] = target_event_id > baseline.get('max_event_id', 0)
            
            # 3. Verify Attendee Linkage
            # Check if the found partner ID is in the event's partner_ids
            if target_partner_id and target_partner_id in event_data[0].get('partner_ids', []):
                result['attendee_link_verified'] = True
            
            # Also check date weekday (0=Mon, 4=Fri)
            start_str = event_data[0].get('start')
            if start_str:
                # Odoo returns strings in UTC usually, but we'll parse safely
                try:
                    dt = datetime.datetime.strptime(start_str, "%Y-%m-%d %H:%M:%S")
                    result['event_weekday'] = dt.weekday()
                    result['event_hour'] = dt.hour
                except:
                    pass

    # Save result
    with open(output_file, 'w') as f:
        json.dump(result, f, default=serialize, indent=2)

    print(f"Export successful. Contact found: {result['contact_found']}, Event found: {result['event_found']}")

except Exception as e:
    print(f"Export failed: {e}", file=sys.stderr)
    # Write a failure result
    with open(output_file, 'w') as f:
        json.dump({"error": str(e)}, f)
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="