#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the final state of the specific contact ID we created
python3 - <<PYEOF
import xmlrpc.client
import sys
import json
import os

try:
    url = 'http://localhost:8069'
    db = 'odoodb'
    username = 'admin'
    password = 'admin'
    
    # Read IDs from setup
    ids = {}
    if os.path.exists('/tmp/task_ids.txt'):
        with open('/tmp/task_ids.txt', 'r') as f:
            for line in f:
                if '=' in line:
                    k, v = line.strip().split('=')
                    ids[k] = int(v)
    
    contact_id = ids.get('CONTACT_ID')
    company_id = ids.get('COMPANY_ID')
    
    result = {
        "contact_found": False,
        "parent_id": None,
        "parent_name": None,
        "job_position": None,
        "mobile": None,
        "target_company_id": company_id,
        "write_date": None
    }
    
    if contact_id:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, username, password, {})
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
        
        # Read fields
        data = models.execute_kw(db, uid, password, 'res.partner', 'read', 
            [[contact_id], ['parent_id', 'function', 'mobile', 'write_date']])
            
        if data:
            record = data[0]
            result["contact_found"] = True
            result["job_position"] = record.get('function')
            result["mobile"] = record.get('mobile')
            result["write_date"] = record.get('write_date')
            
            # parent_id is [id, name] or False
            parent = record.get('parent_id')
            if parent and isinstance(parent, list):
                result["parent_id"] = parent[0]
                result["parent_name"] = parent[1]
    
    # Write result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
        
except Exception as e:
    print(f"Error exporting results: {e}", file=sys.stderr)
    # Write a failure result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json