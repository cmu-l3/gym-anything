#!/bin/bash
echo "=== Exporting enforce_high_value_opportunity_standards result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo via XML-RPC to get the final state of the opportunities
# We output a JSON object directly from Python to a temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 - <<PYEOF > "$TEMP_JSON"
import xmlrpc.client
import json
import sys

url = "${ODOO_URL}"
db = "${ODOO_DB}"
username = "${ODOO_USER}"
password = "${ODOO_PASS}"

result = {
    "timestamp": "${TASK_END}",
    "opportunities": {},
    "tag_exists": False
}

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # Check if 'Key Account' tag exists
    tag_ids = models.execute_kw(db, uid, password, 'crm.tag', 'search', [[['name', '=', 'Key Account']]])
    if tag_ids:
        result["tag_exists"] = True
        key_account_id = tag_ids[0]
    else:
        key_account_id = -1

    # Check specific opportunities
    target_names = ['Global Logistics Contract', 'New HQ Furniture', 'Server Upgrade']
    
    for name in target_names:
        ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', name]]])
        if ids:
            # Read fields: priority, tag_ids
            opp = models.execute_kw(db, uid, password, 'crm.lead', 'read', [ids[0], ['priority', 'tag_ids']])[0]
            
            # Check if Key Account tag is in tag_ids
            has_tag = False
            if key_account_id != -1 and 'tag_ids' in opp:
                has_tag = key_account_id in opp['tag_ids']
            
            result["opportunities"][name] = {
                "exists": True,
                "priority": opp.get('priority', '0'),
                "has_key_account_tag": has_tag
            }
        else:
            result["opportunities"][name] = {
                "exists": False
            }

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="