#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo database for verification data
python3 << 'PYEOF'
import xmlrpc.client
import json
import os
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "reason_created": False,
    "reason_name_correct": False,
    "template_linked": False,
    "template_name_correct": False,
    "applicant_refused": False,
    "applicant_reason_linked": False,
    "reason_create_date": "",
    "task_start_timestamp": 0
}

try:
    # Get task start time
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            result['task_start_timestamp'] = int(f.read().strip())
    except:
        pass

    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check Refuse Reason
    reason_ids = models.execute_kw(db, uid, password, 'hr.applicant.refuse.reason', 'search',
        [[['name', '=', 'Overqualified']]])
    
    if reason_ids:
        result['reason_created'] = True
        result['reason_name_correct'] = True
        
        # Read reason details
        reason_data = models.execute_kw(db, uid, password, 'hr.applicant.refuse.reason', 'read',
            [reason_ids[0]], {'fields': ['template_id', 'create_date']})
        
        if reason_data:
            data = reason_data[0]
            result['reason_create_date'] = data.get('create_date', '')
            
            # Check Template
            template_id = data.get('template_id')
            if template_id:
                result['template_linked'] = True
                # template_id is likely a tuple [id, name] in read result, or check via another read
                if isinstance(template_id, list) or isinstance(template_id, tuple):
                    template_name = template_id[1]
                else:
                    # Fetch name if just ID
                    t_data = models.execute_kw(db, uid, password, 'mail.template', 'read',
                        [template_id], {'fields': ['name']})
                    template_name = t_data[0]['name'] if t_data else ""
                
                if "Recruitment: Refuse" in template_name:
                    result['template_name_correct'] = True

    # 2. Check Applicant Status
    sarah_ids = models.execute_kw(db, uid, password, 'hr.applicant', 'search',
        [[['partner_name', '=', 'Sarah Jenkins'], ['active', '=', False]]])
    
    if sarah_ids:
        result['applicant_refused'] = True
        
        applicant_data = models.execute_kw(db, uid, password, 'hr.applicant', 'read',
            [sarah_ids[0]], {'fields': ['refuse_reason_id']})
        
        if applicant_data:
            refuse_reason = applicant_data[0].get('refuse_reason_id')
            # Check if linked to the specific reason we found/created
            if refuse_reason and reason_ids:
                refuse_reason_id = refuse_reason[0] if isinstance(refuse_reason, (list, tuple)) else refuse_reason
                if refuse_reason_id == reason_ids[0]:
                    result['applicant_reason_linked'] = True

except Exception as e:
    print(f"Error querying Odoo: {e}", file=sys.stderr)
    result['error'] = str(e)

# Write result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true