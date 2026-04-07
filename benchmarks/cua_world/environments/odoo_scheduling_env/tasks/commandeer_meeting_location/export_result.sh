#!/bin/bash
echo "=== Exporting Commandeer Meeting Location results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BASELINE_STANDUP_ID=$(cat /tmp/standup_baseline_id.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo state using Python/XML-RPC
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
baseline_id = int("$BASELINE_STANDUP_ID")

result = {
    "standup_found": False,
    "standup_preserved": False,
    "standup_location": None,
    "audit_found": False,
    "audit_location": None,
    "audit_start": None,
    "audit_stop": None,
    "audit_attendee_names": [],
    "audit_duration_hours": 0.0,
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check Team Standup
    # Search by ID to verify preservation
    standup_data = models.execute_kw(db, uid, password, 'calendar.event', 'read', 
        [[baseline_id], ['name', 'location', 'start']])
    
    if standup_data:
        evt = standup_data[0]
        result['standup_found'] = True
        result['standup_preserved'] = True # Found by original ID
        result['standup_location'] = evt.get('location', '')
    else:
        # Fallback search by name if ID was lost (deleted and recreated)
        standups = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
            [[['name', '=', 'Team Standup']]], {'fields': ['location', 'start'], 'limit': 1})
        if standups:
            result['standup_found'] = True
            result['standup_preserved'] = False
            result['standup_location'] = standups[0].get('location', '')

    # 2. Check External Audit Kickoff
    # Search by name
    audits = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'External Audit Kickoff']]], 
        {'fields': ['location', 'start', 'stop', 'partner_ids'], 'limit': 1})
    
    if audits:
        audit = audits[0]
        result['audit_found'] = True
        result['audit_location'] = audit.get('location', '')
        result['audit_start'] = audit.get('start', '')
        result['audit_stop'] = audit.get('stop', '')
        
        # Calculate duration
        try:
            fmt = "%Y-%m-%d %H:%M:%S"
            start_dt = datetime.strptime(audit['start'], fmt)
            stop_dt = datetime.strptime(audit['stop'], fmt)
            duration = (stop_dt - start_dt).total_seconds() / 3600.0
            result['audit_duration_hours'] = duration
        except:
            pass

        # Fetch attendee names
        partner_ids = audit.get('partner_ids', [])
        if partner_ids:
            partners = models.execute_kw(db, uid, password, 'res.partner', 'read',
                [partner_ids, ['name']])
            result['audit_attendee_names'] = [p['name'] for p in partners]

except Exception as e:
    result['error'] = str(e)

# Write result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="