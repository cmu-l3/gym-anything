#!/bin/bash
echo "=== Exporting remove_meeting_attendee result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if Firefox is running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Query Odoo for the final state of the event
python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

result = {
    "event_exists": False,
    "event_data": {},
    "attendees": {},
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for the event
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Budget Committee Meeting']]],
        {'fields': ['id', 'name', 'partner_ids', 'location', 'description']})

    if events:
        event = events[0]
        result["event_exists"] = True
        result["event_data"] = event
        
        # Resolve partner names for verification
        partner_ids = event['partner_ids'] # List of IDs
        if partner_ids:
            partners = models.execute_kw(db, uid, password, 'res.partner', 'read',
                [partner_ids], {'fields': ['id', 'name']})
            
            # Map ID -> Name
            result["attendees"] = {p['id']: p['name'] for p in partners}
            
            # Also store names list for easier checking
            result["attendee_names"] = [p['name'] for p in partners]

    # Load baseline to compare (anti-gaming)
    if os.path.exists('/tmp/task_baseline.json'):
        with open('/tmp/task_baseline.json', 'r') as f:
            result['baseline'] = json.load(f)

except Exception as e:
    result["error"] = str(e)

# Write result to temp file
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)
PYTHON_EOF

# Construct final JSON with shell variables
# We merge the python output with shell-gathered metrics
jq -n \
    --slurpfile odoo_data /tmp/task_result_temp.json \
    --arg start "$TASK_START" \
    --arg end "$TASK_END" \
    --arg app_running "$APP_RUNNING" \
    '{
        task_start: $start, 
        task_end: $end, 
        app_was_running: $app_running, 
        odoo_state: $odoo_data[0]
    }' > /tmp/task_result.json

# Cleanup
rm -f /tmp/task_result_temp.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="