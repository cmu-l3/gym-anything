#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting add_contact_to_opportunity result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
GEMINI_ID=$(cat /tmp/task_gemini_id.txt 2>/dev/null || echo "0")
OPP_ID=$(cat /tmp/task_opp_id.txt 2>/dev/null || echo "0")

# 3. Query Odoo for Final State via Python
# We need to export a JSON object containing:
# - Contact 'Patricia Williams' details (if exists)
# - Opportunity 'Office Furniture Bulk Order' details
# - IDs and Timestamps

python3 << PYEOF > /tmp/task_result.json
import xmlrpc.client
import json
import sys
from datetime import datetime

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"
task_start_ts = int("$TASK_START")
gemini_id_setup = int("$GEMINI_ID") if "$GEMINI_ID" != "0" else 0

result = {
    "task_start_ts": task_start_ts,
    "gemini_id_setup": gemini_id_setup,
    "contact_found": False,
    "contact": {},
    "opportunity_found": False,
    "opportunity": {}
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # --- Query Contact ---
    # Search for Patricia Williams (individual)
    contact_fields = ['id', 'name', 'parent_id', 'email', 'phone', 'function', 'create_date', 'write_date']
    contacts = models.execute_kw(db, uid, password, 'res.partner', 'search_read',
        [[['name', '=', 'Patricia Williams'], ['is_company', '=', False]]],
        {'fields': contact_fields, 'limit': 1})

    if contacts:
        c = contacts[0]
        result['contact_found'] = True
        
        # Parse timestamps
        create_ts = 0
        if c.get('create_date'):
            dt = datetime.strptime(c['create_date'], '%Y-%m-%d %H:%M:%S')
            create_ts = int(dt.timestamp())
            
        result['contact'] = {
            'id': c['id'],
            'name': c['name'],
            'parent_id': c['parent_id'][0] if c['parent_id'] else None,
            'parent_name': c['parent_id'][1] if c['parent_id'] else None,
            'email': c.get('email', ''),
            'phone': c.get('phone', ''),
            'job_position': c.get('function', ''), # 'function' is the field name for Job Position
            'create_ts': create_ts
        }

    # --- Query Opportunity ---
    opp_fields = ['id', 'name', 'partner_id', 'write_date']
    opps = models.execute_kw(db, uid, password, 'crm.lead', 'search_read',
        [[['name', '=', 'Office Furniture Bulk Order']]],
        {'fields': opp_fields, 'limit': 1})

    if opps:
        o = opps[0]
        result['opportunity_found'] = True
        
        write_ts = 0
        if o.get('write_date'):
            dt = datetime.strptime(o['write_date'], '%Y-%m-%d %H:%M:%S')
            write_ts = int(dt.timestamp())

        result['opportunity'] = {
            'id': o['id'],
            'partner_id': o['partner_id'][0] if o['partner_id'] else None,
            'partner_name': o['partner_id'][1] if o['partner_id'] else None,
            'write_ts': write_ts
        }

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="