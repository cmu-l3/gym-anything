#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PARTNER_ID=$(cat /tmp/target_partner_id.txt 2>/dev/null || echo "0")

# 3. Extract Data via Python
# We query the DB to check the color status of relevant opportunities
python3 - <<PYEOF
import xmlrpc.client
import json
import os
import datetime

url = "${ODOO_URL}"
db = "${ODOO_DB}"
username = "${ODOO_USER}"
password = "${ODOO_PASS}"
target_partner_id = int("${TARGET_PARTNER_ID}")
task_start_ts = int("${TASK_START}")

result = {
    "task_start": task_start_ts,
    "timestamp": str(datetime.datetime.now()),
    "targets": [],
    "distractors": [],
    "app_running": False
}

try:
    # Check if Odoo accessible
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    if uid:
        result["app_running"] = True
        models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

        # Fetch Targets (Azure Interior)
        # We assume the ones created in setup are the main ones, but we fetch all active ops for this partner
        target_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', 
            [[['partner_id', '=', target_partner_id], ['type', '=', 'opportunity']]])
        
        if target_ids:
            targets_data = models.execute_kw(db, uid, password, 'crm.lead', 'read', 
                [target_ids], {'fields': ['id', 'name', 'color', 'write_date']})
            result["targets"] = targets_data

        # Fetch Distractors (Everything else created recently or visible)
        # To avoid fetching thousands of records, we limit to the partners we seeded in setup + some others
        # Ideally, we check if ANY non-target opportunity has a color
        distractor_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', 
            [[['partner_id', '!=', target_partner_id], ['type', '=', 'opportunity'], ['color', '!=', 0]]])
        
        # Also fetch a sample of uncolored distractors just to prove they exist
        sample_distractor_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', 
            [[['partner_id', '!=', target_partner_id], ['type', '=', 'opportunity'], ['color', '=', 0]]],
            {'limit': 5})
        
        all_distractor_ids = list(set(distractor_ids + sample_distractor_ids))
        
        if all_distractor_ids:
            distractors_data = models.execute_kw(db, uid, password, 'crm.lead', 'read', 
                [all_distractor_ids], {'fields': ['id', 'name', 'color', 'write_date']})
            result["distractors"] = distractors_data

except Exception as e:
    result["error"] = str(e)

# Write result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)

PYEOF

# 4. Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="