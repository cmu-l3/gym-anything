#!/bin/bash
set -e
echo "=== Exporting rename_calendar_event results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read the start time and original event ID
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORIGINAL_EVENT_ID=$(cat /tmp/target_event_id.txt 2>/dev/null || echo "0")

# Run Python script to query Odoo state and export to JSON
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
original_id = int("$ORIGINAL_EVENT_ID")
task_start_ts = float("$TASK_START_TIME")

result = {
    "original_name_exists": False,
    "target_name_found": False,
    "target_event_details": {},
    "same_id_reused": False,
    "write_date_valid": False,
    "total_event_count": 0
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check if original name still exists
    orig_name_query = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                                      [[['name', '=', 'Marketing Campaign Review']]])
    result['original_name_exists'] = bool(orig_name_query)

    # 2. Check if target name exists
    target_name = "Q3 Marketing Results & Q4 Strategy Planning"
    target_query = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
                                   [[['name', '=', target_name]]],
                                   {'fields': ['id', 'name', 'location', 'description', 'partner_ids', 'write_date']})
    
    if target_query:
        result['target_name_found'] = True
        event = target_query[0]
        
        # Get attendee names for easier verification
        attendee_names = []
        if event.get('partner_ids'):
            partners = models.execute_kw(db, uid, password, 'res.partner', 'read',
                                       [event['partner_ids'], ['name']])
            attendee_names = [p['name'] for p in partners]
            
        result['target_event_details'] = {
            'id': event.get('id'),
            'location': event.get('location'),
            'description': event.get('description'),
            'attendees': attendee_names
        }
        
        # 3. Check if ID matches original (In-place edit vs Delete+Create)
        if original_id > 0 and event.get('id') == original_id:
            result['same_id_reused'] = True
            
        # 4. Check write_date (Anti-gaming)
        write_date_str = event.get('write_date')
        if write_date_str:
            # Odoo returns UTC usually, or naive string. 
            # Simple timestamp comparison:
            try:
                wd = datetime.datetime.strptime(write_date_str, '%Y-%m-%d %H:%M:%S')
                # Adjust for potential timezone differences if needed, but relative comparison usually ok
                # Assuming Odoo server time and system time are sync'd in container
                # We'll rely on the fact that write_date should be recent
                pass
            except:
                pass
            # For simplicity in this script, we pass the raw string and handle logic in verifier
            result['write_date'] = write_date_str

    # 5. Total count check (sanity)
    result['total_event_count'] = models.execute_kw(db, uid, password, 'calendar.event', 'search_count', [[]])

except Exception as e:
    result['error'] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYTHON_EOF

# Set permissions so the host can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true