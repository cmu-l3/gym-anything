#!/bin/bash
echo "=== Exporting batch_add_attendee results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get the target date range calculated in setup
START_DATE=$(cat /tmp/target_start_date.txt 2>/dev/null || date -I)
END_DATE=$(cat /tmp/target_end_date.txt 2>/dev/null || date -I)

# 3. Query Odoo for the final state of events in the target week
# We need to know:
# - Event Name
# - Attendees (List of names)
# - Was Alice an attendee? (Target vs Distractor)
# - Is James an attendee? (Success metric)
# - Write Date (Anti-gaming)

python3 << EOF
import xmlrpc.client
import json
import sys

url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'

output = {
    "events": [],
    "target_start": "$START_DATE",
    "target_end": "$END_DATE",
    "task_start_ts": 0
}

# Load task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        output['task_start_ts'] = float(f.read().strip())
except:
    pass

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Define the week range
    domain = [
        ['start', '>=', '$START_DATE 00:00:00'],
        ['stop', '<=', '$END_DATE 23:59:59']
    ]

    # Fetch all events in that week
    fields = ['name', 'partner_ids', 'write_date']
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read', [domain], {'fields': fields})

    # Fetch partner names to map IDs to strings
    all_partner_ids = set()
    for e in events:
        all_partner_ids.update(e['partner_ids'])
    
    if all_partner_ids:
        partners = models.execute_kw(db, uid, password, 'res.partner', 'read', [list(all_partner_ids)], {'fields': ['name']})
        id_to_name = {p['id']: p['name'] for p in partners}
    else:
        id_to_name = {}

    processed_events = []
    for e in events:
        attendees = [id_to_name.get(pid, 'Unknown') for pid in e['partner_ids']]
        processed_events.append({
            "id": e['id'],
            "name": e['name'],
            "attendees": attendees,
            "write_date": e['write_date']
        })

    output['events'] = processed_events
    
except Exception as e:
    output['error'] = str(e)
    print(f"Error exporting data: {e}", file=sys.stderr)

# Write to temp file first
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(output, f, indent=2)

EOF

# 4. Secure move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Data saved to /tmp/task_result.json"
cat /tmp/task_result.json