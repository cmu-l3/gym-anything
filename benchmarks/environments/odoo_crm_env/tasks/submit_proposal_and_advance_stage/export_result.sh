#!/bin/bash
echo "=== Exporting Submit Proposal Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the final state
python3 - << 'PYEOF' > /tmp/task_result.json
import xmlrpc.client
import json
import os
import time

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
password = "admin"

result = {
    "opportunity_found": False,
    "stage_name": "Unknown",
    "probability": 0.0,
    "attachment_found": False,
    "attachment_name": "",
    "timestamp": time.time()
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Find the Opportunity
    leads = models.execute_kw(db, uid, password, 'crm.lead', 'search_read', 
        [[['name', '=', 'Office Design Project - Azure Interior']]], 
        {'fields': ['id', 'stage_id', 'probability']})
    
    if leads:
        lead = leads[0]
        result["opportunity_found"] = True
        result["probability"] = lead['probability']
        
        # stage_id is a tuple [id, "Name"]
        if lead['stage_id']:
            result["stage_name"] = lead['stage_id'][1]
        
        lead_id = lead['id']

        # 2. Check Attachments
        # Search for attachment linked to this lead
        attachments = models.execute_kw(db, uid, password, 'ir.attachment', 'search_read',
            [[['res_model', '=', 'crm.lead'], ['res_id', '=', lead_id]]],
            {'fields': ['name', 'create_date']})
        
        target_filename = "Azure_Interior_Renovation_v2.pdf"
        
        for att in attachments:
            if target_filename in att['name']:
                result["attachment_found"] = True
                result["attachment_name"] = att['name']
                break

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

echo "Result JSON generated:"
cat /tmp/task_result.json

# Cleanup permission for export
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="