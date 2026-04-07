#!/bin/bash
set -e
echo "=== Setting up substitute_meeting_attendee task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset the specific event to a known initial state via Python/XML-RPC
# We ensure 'Marketing Campaign Review' has [Alice Johnson, Carol Martinez] as attendees
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    # Connect
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Resolve Partner IDs
    partner_names = ['Alice Johnson', 'Carol Martinez', 'David Chen']
    partners = models.execute_kw(db, uid, password, 'res.partner', 'search_read',
        [[['name', 'in', partner_names]]],
        {'fields': ['id', 'name']})
    
    p_map = {p['name']: p['id'] for p in partners}
    
    # Validation
    if not all(k in p_map for k in partner_names):
        print(f"Error: Could not find all partners. Found: {p_map.keys()}", file=sys.stderr)
        sys.exit(1)

    # 2. Find the Event
    event_name = "Marketing Campaign Review"
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', event_name]]],
        {'fields': ['id', 'name', 'start']})

    if not events:
        print(f"Error: Event '{event_name}' not found.", file=sys.stderr)
        sys.exit(1)

    event_id = events[0]['id']
    
    # 3. Reset Attendees to [Alice, Carol] (IDs)
    # The (6, 0, [ids]) command replaces all existing relations with the new list
    new_attendee_ids = [p_map['Alice Johnson'], p_map['Carol Martinez']]
    
    models.execute_kw(db, uid, password, 'calendar.event', 'write',
        [[event_id], {'partner_ids': [(6, 0, new_attendee_ids)]}])

    print(f"Successfully reset event {event_id} attendees to Alice and Carol.")

    # Record initial ID for verification
    with open('/tmp/initial_event_id.txt', 'w') as f:
        f.write(str(event_id))

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Calendar
# We use ensure_firefox from task_utils to handle the profile lock/clean start
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="