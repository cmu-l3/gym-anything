#!/bin/bash
echo "=== Exporting Link Orphaned Opportunities results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the current state of the opportunities
python3 << PYEOF
import xmlrpc.client
import json
import os
import datetime

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))
except Exception as e:
    print(json.dumps({"error": str(e)}))
    exit(1)

opp_names = [
    'Office Design Project - Gemini',
    'Q3 Consultation Services',
    'Software License Renewal - Deco Addict'
]

# Fetch opportunities
# We need to get: partner_id (name), write_date
opp_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', 'in', opp_names]]])
opps = models.execute_kw(db, uid, password, 'crm.lead', 'read', [opp_ids], {'fields': ['name', 'partner_id', 'write_date']})

results = {}
for opp in opps:
    # partner_id is returned as [id, name] or False
    partner_name = opp['partner_id'][1] if opp['partner_id'] else None
    
    results[opp['name']] = {
        "partner_name": partner_name,
        "write_date": opp['write_date']
    }

output = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "opportunities": results,
    "screenshot_path": "/tmp/task_final.png"
}

# Write to temp file
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(output, f)

PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="