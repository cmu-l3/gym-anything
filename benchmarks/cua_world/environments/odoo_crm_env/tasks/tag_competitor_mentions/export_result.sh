#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for results
python3 - <<PYEOF
import xmlrpc.client
import json
import sys
import time

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check Tag Existence
    target_tag = "Competitor: OmniTech"
    tag_ids = models.execute_kw(db, uid, password, 'crm.tag', 'search', [[['name', '=', target_tag]]])
    tag_exists = bool(tag_ids)
    tag_id = tag_ids[0] if tag_ids else None
    
    tag_create_date = ""
    if tag_id:
        tag_data = models.execute_kw(db, uid, password, 'crm.tag', 'read', [tag_id, ['create_date']])
        tag_create_date = tag_data[0]['create_date']

    # 2. Check Leads and their tags
    leads_to_check = [
        "Office Expansion - KwikE Mart",
        "Server Upgrade - CyberDyne Systems",
        "Fleet Management - Planet Express",
        "Consulting Services - Wayne Enterprises",
        "Software License - Stark Industries"
    ]
    
    lead_results = {}
    
    for name in leads_to_check:
        l_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', name]]])
        if l_ids:
            lead = models.execute_kw(db, uid, password, 'crm.lead', 'read', [l_ids[0], ['name', 'tag_ids', 'description']])
            
            # Check if our target tag is in the tag_ids list
            has_tag = False
            if tag_id and tag_id in lead[0]['tag_ids']:
                has_tag = True
                
            lead_results[name] = {
                "has_target_tag": has_tag,
                "description_snippet": lead[0]['description'][:50] if lead[0]['description'] else ""
            }

    result = {
        "tag_exists": tag_exists,
        "tag_id": tag_id,
        "tag_create_date": tag_create_date,
        "leads": lead_results,
        "task_start_ts": ${TASK_START},
        "task_end_ts": ${TASK_END}
    }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=4)

except Exception as e:
    print(f"Error exporting data: {e}", file=sys.stderr)
    # Write a failure result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)

PYEOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json