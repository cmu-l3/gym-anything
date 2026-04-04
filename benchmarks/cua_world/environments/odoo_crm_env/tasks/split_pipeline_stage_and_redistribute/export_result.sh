#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo database state using Python and export to JSON
python3 - << 'PYEOF'
import xmlrpc.client
import json
import os
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
except Exception as e:
    print(f"Error connecting to Odoo: {e}")
    sys.exit(1)

# Fetch Stages
stages = models.execute_kw(db, uid, password, 'crm.stage', 'search_read',
    [[]], {'fields': ['id', 'name', 'sequence'], 'order': 'sequence'})

# Fetch Leads (Specific ones we care about)
target_names = [
    "Global Logistics Contract", "Enterprise License Upgrade", "Q3 Managed Services",
    "Office Expansion Inquiry", "Initial Consultation", "Hardware Refresh Estimate"
]
leads = models.execute_kw(db, uid, password, 'crm.lead', 'search_read',
    [[['name', 'in', target_names]]], 
    {'fields': ['name', 'stage_id', 'probability', 'write_date']})

# Prepare result dict
result = {
    "stages": stages,
    "leads": leads,
    "task_start": int(os.environ.get('TASK_START', 0)),
    "task_end": int(os.environ.get('TASK_END', 0))
}

# Write to temp file first
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Move result to final location with safe permissions
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="