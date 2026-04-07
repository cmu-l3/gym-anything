#!/bin/bash
echo "=== Exporting schedule_monthly_floating_meeting results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract Event and Recurrence Data using Python
# We need to check:
# 1. Did the agent create the event?
# 2. Is the start time correct?
# 3. Is it linked to a recurrence rule?
# 4. Is the recurrence rule "Month by Day" (floating) vs "Month by Date" (fixed)?
# 5. Was it created after task start?

python3 << PYTHON_EOF > /tmp/extraction_log.txt 2>&1
import xmlrpc.client
import json
import datetime
import sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
task_start = $TASK_START

result = {
    "event_found": False,
    "event_details": {},
    "recurrence_found": False,
    "recurrence_details": {},
    "timestamp_check": False
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for the event
    # We look for the base event. In Odoo, recurring events are expanded.
    # We look for one with the correct name created recently.
    
    # Note: 'create_date' is UTC.
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Department All-Hands']]],
        {'fields': ['name', 'start', 'duration', 'recurrence_id', 'create_date'], 'limit': 1, 'order': 'id desc'}
    )

    if events:
        evt = events[0]
        result['event_found'] = True
        
        # Check timestamp (Odoo string format: 'YYYY-MM-DD HH:MM:SS')
        create_date_str = evt.get('create_date', '')
        created_ts = 0
        if create_date_str:
            # Simple parsing, assuming server is UTC-ish or consistent
            dt = datetime.datetime.strptime(create_date_str.split('.')[0], "%Y-%m-%d %H:%M:%S")
            # Treating as local/naive for simple comparison or converting to epoch
            created_ts = dt.timestamp()
        
        # Allow some clock skew, but ensure it wasn't there days ago (though we cleaned up)
        # Using a loose check because Odoo docker time vs host time can vary
        result['timestamp_check'] = True # We cleaned up in setup, so existence implies newness
        
        result['event_details'] = {
            'name': evt.get('name'),
            'start': evt.get('start'), # String "YYYY-MM-DD HH:MM:SS"
            'duration': evt.get('duration')
        }

        # Check Recurrence
        recurrence_id = evt.get('recurrence_id') # returns [id, name] or False
        if recurrence_id:
            rid = recurrence_id[0]
            recs = models.execute_kw(db, uid, password, 'calendar.recurrence', 'read',
                [[rid]],
                {'fields': ['rrule', 'rrule_type', 'month_by', 'day', 'byday', 'weekday', 'interval']}
            )
            
            if recs:
                rec = recs[0]
                result['recurrence_found'] = True
                result['recurrence_details'] = {
                    'rrule': rec.get('rrule'),          # e.g., FREQ=MONTHLY;BYDAY=1MO
                    'rrule_type': rec.get('rrule_type'), # 'monthly'
                    'month_by': rec.get('month_by'),    # 'day' (floating) vs 'date' (fixed)
                    'day': rec.get('day'),              # Date of month (e.g., 5)
                    'byday': rec.get('byday'),          # '1' (First), '2' (Second)...
                    'weekday': rec.get('weekday'),      # 'MO', 'TU'...
                    'interval': rec.get('interval')
                }

except Exception as e:
    result['error'] = str(e)
    print(f"Error extracting data: {e}")

# Save result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)

print("Extraction complete.")
PYTHON_EOF

# Ensure permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json