#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query Odoo DB and export state to JSON
# We do this inside the container to access xmlrpc locally and reliably
python3 - <<PYEOF
import xmlrpc.client
import json
import sys
import os
import datetime

url = "${ODOO_URL}"
db = "${ODOO_DB}"
username = "${ODOO_USER}"
password = "${ODOO_PASS}"
task_start = float(${TASK_START})

output = {
    "task_start": task_start,
    "timestamp": str(datetime.datetime.now()),
    "master_record": None,
    "duplicate_record": None,
    "opportunities": {},
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    MASTER_NAME = "Hyperion Systems Inc."
    DUPE_NAME = "Hyperion Systems"

    # 1. Fetch Master Record
    # We search specifically for the name
    master_ids = models.execute_kw(db, uid, password, 'res.partner', 'search', 
        [[['name', '=', MASTER_NAME]]])
    
    if master_ids:
        # Read fields: email, write_date
        master_data = models.execute_kw(db, uid, password, 'res.partner', 'read', 
            [master_ids[0], ['id', 'name', 'email', 'active', 'write_date']])
        output['master_record'] = master_data[0]

    # 2. Fetch Duplicate Record
    # Note: Search defaults to active=True. We must check if it's archived (active=False).
    # search(..., limit=1) defaults to active records.
    # To find archived, we add ['active', 'in', [False, True]] or use specific domain.
    
    # First check if it exists as Active
    dupe_active_ids = models.execute_kw(db, uid, password, 'res.partner', 'search', 
        [[['name', '=', DUPE_NAME]]])
    
    # Then check if it exists as Inactive (Archived)
    dupe_inactive_ids = models.execute_kw(db, uid, password, 'res.partner', 'search', 
        [[['name', '=', DUPE_NAME], ['active', '=', False]]])
    
    dupe_id = None
    if dupe_active_ids:
        dupe_id = dupe_active_ids[0]
    elif dupe_inactive_ids:
        dupe_id = dupe_inactive_ids[0]
        
    if dupe_id:
        dupe_data = models.execute_kw(db, uid, password, 'res.partner', 'read', 
            [dupe_id, ['id', 'name', 'email', 'active', 'write_date']])
        output['duplicate_record'] = dupe_data[0]

    # 3. Check Opportunities
    target_opps = ['Solar Panel Array - Commercial', 'Battery Backup System', 'Inverter Upgrade']
    
    for opp_name in target_opps:
        opp_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', 
            [[['name', '=', opp_name]]])
        if opp_ids:
            opp_data = models.execute_kw(db, uid, password, 'crm.lead', 'read', 
                [opp_ids[0], ['name', 'partner_id', 'write_date']])
            # partner_id is returned as [id, name]
            pid = opp_data[0]['partner_id'][0] if opp_data[0]['partner_id'] else None
            pname = opp_data[0]['partner_id'][1] if opp_data[0]['partner_id'] else None
            
            output['opportunities'][opp_name] = {
                'partner_id': pid,
                'partner_name': pname,
                'write_date': opp_data[0]['write_date']
            }

except Exception as e:
    output['error'] = str(e)

# Write to temp file first
with open('/tmp/result_temp.json', 'w') as f:
    json.dump(output, f, indent=2)

PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="