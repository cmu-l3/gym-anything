#!/bin/bash
echo "=== Exporting schedule_non_attending_meeting results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python script to query Odoo and export result to JSON
python3 << PYTHON_EOF
import xmlrpc.client
import json
import datetime
import sys

url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'

result_data = {
    "event_found": False,
    "event_details": {},
    "attendee_names": [],
    "attendee_ids": [],
    "admin_is_attendee": False,
    "created_after_start": False,
    "task_start_ts": $TASK_START
}

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))
    
    # 1. Search for the event by name
    # We use ilike for case-insensitivity
    event_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', 'ilike', 'Executive Severance Review']]])
    
    if event_ids:
        # Get the most recently created one if multiple match
        # (Though we cleaned up in setup, agent might have created multiple)
        events = models.execute_kw(db, uid, password, 'calendar.event', 'read',
            [event_ids], 
            ['name', 'start', 'location', 'partner_ids', 'create_date'])
            
        # Sort by create_date desc
        events.sort(key=lambda x: x['create_date'], reverse=True)
        event = events[0]
        
        result_data["event_found"] = True
        result_data["event_details"] = {
            "name": event.get('name'),
            "start": event.get('start'),
            "location": event.get('location'),
            "create_date": event.get('create_date')
        }
        
        # Check creation time against task start
        # Odoo dates are UTC strings usually. Convert to timestamp.
        # Format: '2023-10-25 14:30:00'
        try:
            create_dt = datetime.datetime.strptime(event['create_date'], "%Y-%m-%d %H:%M:%S")
            # Odoo stores in UTC (usually), system time might be local or UTC. 
            # Docker env usually UTC. Simple timestamp comparison.
            # However, simpler check: did we find it? Setup deleted old ones.
            # So if found, it's likely new. But let's try strict check.
            pass
        except:
            pass

        # 2. Get Attendee Names
        partner_ids = event.get('partner_ids', [])
        result_data["attendee_ids"] = partner_ids
        
        if partner_ids:
            partners = models.execute_kw(db, uid, password, 'res.partner', 'read',
                [partner_ids], ['name'])
            
            attendee_names = [p['name'] for p in partners]
            result_data["attendee_names"] = attendee_names
            
            # Check for Administrator
            # Admin usually named "Administrator" or "Mitchell Admin" or matches current user
            # We check for the specific name "Administrator" which is default in this env
            # OR check if the uid's partner_id is in the list
            
            user_info = models.execute_kw(db, uid, password, 'res.users', 'read', [uid], ['partner_id'])
            current_user_partner_id = user_info[0]['partner_id'][0]
            
            if current_user_partner_id in partner_ids:
                result_data["admin_is_attendee"] = True
            
            # Fallback name check
            for name in attendee_names:
                if "Administrator" in name or "Mitchell Admin" in name:
                    result_data["admin_is_attendee"] = True

except Exception as e:
    result_data["error"] = str(e)

# Save to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result_data, f, indent=2)

print("Export complete.")
PYTHON_EOF

# Secure the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

cat /tmp/task_result.json
echo "=== Export complete ==="