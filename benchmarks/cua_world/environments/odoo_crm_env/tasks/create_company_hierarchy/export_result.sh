#!/bin/bash
set -e
echo "=== Exporting create_company_hierarchy results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract data from Odoo using Python XML-RPC to get structured data
# We'll save this to a JSON file for the verifier to read
python3 - <<PYEOF
import xmlrpc.client
import json
import os
import datetime

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
passwd = "admin"

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "records": {}
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, passwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    target_names = [
        "Nexus Global Industries",
        "Nexus Global - Europe",
        "Nexus Global - Asia Pacific",
        "Elena Rossi",
        "Kenji Tanaka"
    ]

    fields = [
        'name', 'is_company', 'parent_id', 'street', 'city', 'zip', 'country_id',
        'phone', 'website', 'email', 'function', 'create_date', 'company_type'
    ]

    for name in target_names:
        ids = models.execute_kw(db, uid, passwd, 'res.partner', 'search', [[['name', '=', name]]])
        if ids:
            # Fetch the most recently created one if duplicates exist
            records = models.execute_kw(db, uid, passwd, 'res.partner', 'read', [ids], {'fields': fields})
            # Sort by ID descending
            records.sort(key=lambda x: x['id'], reverse=True)
            result["records"][name] = records[0]
        else:
            result["records"][name] = None

except Exception as e:
    result["error"] = str(e)

# Save to temporary JSON file
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"