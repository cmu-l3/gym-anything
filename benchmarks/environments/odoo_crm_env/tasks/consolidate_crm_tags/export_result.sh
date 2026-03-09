#!/bin/bash
echo "=== Exporting task results: consolidate_crm_tags@1 ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to query Odoo and generate a clean JSON result
# We do this inside the container to access the internal Odoo instance
python3 - <<PYEOF
import xmlrpc.client
import json
import sys
import os

url = "${ODOO_URL}"
db = "${ODOO_DB}"
username = "${ODOO_USER}"
password = "${ODOO_PASS}"

result = {
    "task_start": ${TASK_START},
    "task_end": ${TASK_END},
    "opportunities": {},
    "tags_status": {},
    "app_running": False
}

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))
    result["app_running"] = True
    
    # 1. Check if "Urgent" tag exists and get its ID
    urgent_tags = models.execute_kw(db, uid, password, 'crm.tag', 'search', [[['name', '=', 'Urgent']]])
    urgent_tag_id = urgent_tags[0] if urgent_tags else None
    result["tags_status"]["Urgent_exists"] = bool(urgent_tag_id)
    
    # 2. Check if bad tags still exist
    bad_urgent = models.execute_kw(db, uid, password, 'crm.tag', 'search', [[['name', '=', 'urgent']]])
    bad_asap = models.execute_kw(db, uid, password, 'crm.tag', 'search', [[['name', '=', 'ASAP']]])
    
    result["tags_status"]["urgent_deleted"] = len(bad_urgent) == 0
    result["tags_status"]["ASAP_deleted"] = len(bad_asap) == 0
    
    # IDs of bad tags (if they still exist)
    bad_ids = []
    if bad_urgent: bad_ids.append(bad_urgent[0])
    if bad_asap: bad_ids.append(bad_asap[0])
    
    # 3. Check target opportunities
    targets = [
        'Emergency Generators - Apex Corp',
        'Rush Order - Beta Industries',
        'Expedited Shipping - Gamma Inc'
    ]
    
    leads = models.execute_kw(db, uid, password, 'crm.lead', 'search_read', 
        [[['name', 'in', targets]]], 
        {'fields': ['name', 'tag_ids']})
        
    for lead in leads:
        name = lead['name']
        tag_ids = lead['tag_ids']
        
        has_correct_tag = False
        if urgent_tag_id and urgent_tag_id in tag_ids:
            has_correct_tag = True
            
        has_bad_tag = False
        for bad_id in bad_ids:
            if bad_id in tag_ids:
                has_bad_tag = True
                
        # Also check names of tags if IDs fail (double check)
        if tag_ids:
            tag_recs = models.execute_kw(db, uid, password, 'crm.tag', 'read', [tag_ids, ['name']])
            tag_names = [t['name'] for t in tag_recs]
            if 'Urgent' in tag_names: has_correct_tag = True
            if 'urgent' in tag_names or 'ASAP' in tag_names: has_bad_tag = True
            
        result["opportunities"][name] = {
            "has_correct_tag": has_correct_tag,
            "has_bad_tag": has_bad_tag
        }

except Exception as e:
    result["error"] = str(e)
    print(f"Error querying Odoo: {e}")

# Save to temp file first
with open('/tmp/result_temp.json', 'w') as f:
    json.dump(result, f)

PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="