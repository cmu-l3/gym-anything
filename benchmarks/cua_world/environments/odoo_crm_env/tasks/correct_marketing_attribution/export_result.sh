#!/bin/bash
echo "=== Exporting correct_marketing_attribution results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query database and export results to JSON
python3 - <<PYEOF
import xmlrpc.client
import json
import sys
import datetime

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "opportunities": {},
    "utm_ids": {}
}

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # 1. Get Expected UTM IDs for comparison
    camp_ids = models.execute_kw(db, uid, password, 'utm.campaign', 'search', [[['name', '=', 'Summer 2025 Promotion']]])
    med_ids = models.execute_kw(db, uid, password, 'utm.medium', 'search', [[['name', '=', 'Email']]])
    src_ids = models.execute_kw(db, uid, password, 'utm.source', 'search', [[['name', '=', 'Newsletter']]])
    
    result['utm_ids'] = {
        'campaign_id': camp_ids[0] if camp_ids else None,
        'medium_id': med_ids[0] if med_ids else None,
        'source_id': src_ids[0] if src_ids else None
    }

    # 2. Query Opportunities
    target_names = [
        "Fleet Management Software - Logistics Inc",
        "Inventory Control System - Warehouse Co",
        "ERP Implementation - Manufacturing Ltd"
    ]
    
    for name in target_names:
        ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', name]]])
        if ids:
            # Read fields including write_date to check modification time
            fields = ['campaign_id', 'medium_id', 'source_id', 'write_date']
            data = models.execute_kw(db, uid, password, 'crm.lead', 'read', [ids[0], fields])[0]
            
            # Odoo returns Many2one as [id, name] or False
            # We standardize to ID or None
            camp = data.get('campaign_id')
            med = data.get('medium_id')
            src = data.get('source_id')
            
            result['opportunities'][name] = {
                'found': True,
                'campaign_id': camp[0] if camp else None,
                'medium_id': med[0] if med else None,
                'source_id': src[0] if src else None,
                'campaign_name': camp[1] if camp else None,
                'write_date': data.get('write_date')
            }
        else:
            result['opportunities'][name] = {'found': False}

except Exception as e:
    result['error'] = str(e)

# Save to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)

print("Exported JSON result")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="