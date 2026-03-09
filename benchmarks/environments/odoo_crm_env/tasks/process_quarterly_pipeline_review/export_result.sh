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
    "hyperion": None,
    "zenith": None,
    "apex": None,
    "connection_error": False
}

try:
    common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USER, PASS, {})
    models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')

    # Fetch Hyperion
    hyperion_data = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search_read', 
        [[['name', '=', 'Cloud Migration - Hyperion Systems'], ['active', 'in', [True, False]]]], 
        {'fields': ['id', 'active', 'lost_reason_id', 'write_date']})
    
    if hyperion_data:
        # lost_reason_id is [id, name] or False
        reason = hyperion_data[0]['lost_reason_id']
        result['hyperion'] = {
            'exists': True,
            'active': hyperion_data[0]['active'],
            'lost_reason': reason[1] if reason else None,
            'write_date': hyperion_data[0]['write_date']
        }
    else:
        result['hyperion'] = {'exists': False}

    # Fetch Zenith
    zenith_data = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search_read',
        [[['name', '=', 'ERP Implementation - Zenith Corp']]],
        {'fields': ['id', 'tag_ids', 'priority', 'write_date']})
        
    if zenith_data:
        # Resolve tags
        tag_ids = zenith_data[0]['tag_ids']
        tag_names = []
        if tag_ids:
            tags = models.execute_kw(DB, uid, PASS, 'crm.tag', 'read', [tag_ids], {'fields': ['name']})
            tag_names = [t['name'] for t in tags]
            
        result['zenith'] = {
            'exists': True,
            'tags': tag_names,
            'priority': str(zenith_data[0]['priority']), # '0', '1', '2', '3'
            'write_date': zenith_data[0]['write_date']
        }
    else:
        result['zenith'] = {'exists': False}
    
    # Fetch Apex
    apex_data = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search_read',
        [[['name', '=', 'Consulting Retainer - Apex Global']]],
        {'fields': ['id', 'stage_id', 'probability', 'write_date']})
        
    if apex_data:
        stage = apex_data[0]['stage_id'] # [id, name]
        result['apex'] = {
            'exists': True,
            'stage': stage[1] if stage else None,
            'probability': apex_data[0]['probability'],
            'write_date': apex_data[0]['write_date']
        }
    else:
        result['apex'] = {'exists': False}

except Exception as e:
    result['connection_error'] = True
    result['error_msg'] = str(e)

# Write result to temp file then move
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(result, f, indent=2)

os.replace('/tmp/temp_result.json', output_file)
os.chmod(output_file, 0o666)

print("Export complete.")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="