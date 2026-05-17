#!/bin/bash
echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

# Get task start time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query Odoo and export JSON
python3 << PYEOF
import xmlrpc.client
import json
import sys
import os

ODOO_URL = "http://localhost:8069"
DB = "odoodb"
USER = "admin"
PASS = "admin"

output_file = "/tmp/task_result.json"

result = {
    "start_time": $START_TIME,
    "export_time": $EXPORT_TIME,
    "weis": None,
    "vse": None,
    "insteel": None,
    "connection_error": False
}

try:
    common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USER, PASS, {})
    models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')

    # Fetch Weis Markets (expected: marked Lost with reason "Too Expensive")
    weis_data = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search_read',
        [[['name', '=', 'Cloud Migration - Weis Markets'], ['active', 'in', [True, False]]]],
        {'fields': ['id', 'active', 'lost_reason_id', 'write_date']})

    if weis_data:
        reason = weis_data[0]['lost_reason_id']
        result['weis'] = {
            'exists': True,
            'active': weis_data[0]['active'],
            'lost_reason': reason[1] if reason else None,
            'write_date': weis_data[0]['write_date']
        }
    else:
        result['weis'] = {'exists': False}

    # Fetch VSE Corporation (expected: "At Risk" tag + Priority 0)
    vse_data = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search_read',
        [[['name', '=', 'ERP Rollout - VSE Corporation']]],
        {'fields': ['id', 'tag_ids', 'priority', 'write_date']})

    if vse_data:
        tag_ids = vse_data[0]['tag_ids']
        tag_names = []
        if tag_ids:
            tags = models.execute_kw(DB, uid, PASS, 'crm.tag', 'read',
                                     [tag_ids], {'fields': ['name']})
            tag_names = [t['name'] for t in tags]

        result['vse'] = {
            'exists': True,
            'tags': tag_names,
            'priority': str(vse_data[0]['priority']),
            'write_date': vse_data[0]['write_date']
        }
    else:
        result['vse'] = {'exists': False}

    # Fetch Insteel Industries (expected: Negotiation stage + 90% probability)
    insteel_data = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search_read',
        [[['name', '=', 'Consulting Retainer - Insteel Industries']]],
        {'fields': ['id', 'stage_id', 'probability', 'write_date']})

    if insteel_data:
        stage = insteel_data[0]['stage_id']
        result['insteel'] = {
            'exists': True,
            'stage': stage[1] if stage else None,
            'probability': insteel_data[0]['probability'],
            'write_date': insteel_data[0]['write_date']
        }
    else:
        result['insteel'] = {'exists': False}

except Exception as e:
    result['connection_error'] = True
    result['error_msg'] = str(e)

with open('/tmp/temp_result.json', 'w') as f:
    json.dump(result, f, indent=2)

os.replace('/tmp/temp_result.json', output_file)
os.chmod(output_file, 0o666)

print("Export complete.")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="
