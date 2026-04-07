#!/bin/bash
echo "=== Exporting convert_meeting_to_recurring_schedule result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the final state of the event
# We need to check the recurrence settings
python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'

result = {
    "event_found": False,
    "is_recurring": False,
    "recurrence_data": {},
    "event_data": {}
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find the event "Team Standup"
    # Note: If it's recurring, Odoo might split it into virtual events.
    # We look for the base event or one of the occurrences.
    # Using 'active', True to find it even if future instances are generated.
    domain = [['name', '=', 'Team Standup']]
    fields = ['id', 'name', 'recurrence_id', 'location', 'description', 'partner_ids']
    
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read', [domain], {'fields': fields, 'limit': 1})

    if events:
        event = events[0]
        result["event_found"] = True
        result["event_data"] = event
        
        recurrence_id = event.get('recurrence_id')
        
        if recurrence_id:
            # recurrence_id is a tuple (id, name) in search_read
            rid = recurrence_id[0]
            result["is_recurring"] = True
            
            # Fetch recurrence details
            r_fields = ['rrule_type', 'interval', 'count', 'end_type', 
                        'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
            r_data = models.execute_kw(db, uid, password, 'calendar.recurrence', 'read', 
                                       [[rid]], {'fields': r_fields})
            
            if r_data:
                result["recurrence_data"] = r_data[0]
    
except Exception as e:
    result["error"] = str(e)

with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result exported to {output_file}")
PYTHON_EOF

# Set permissions so verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="