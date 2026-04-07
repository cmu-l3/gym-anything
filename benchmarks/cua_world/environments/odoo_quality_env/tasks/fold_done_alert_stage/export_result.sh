#!/bin/bash
echo "=== Exporting fold_done_alert_stage results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve the current state of the stage from Odoo
echo "Querying Odoo for final stage state..."
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import os

url = "http://localhost:8069"
db = "odoo_quality"
username = "admin"
password = "admin"

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "stage_exists": False,
    "fold_state": False,
    "stage_name": "",
    "write_date": "",
    "screenshot_path": "/tmp/task_final.png"
}

try:
    # Get target ID from setup
    target_id = 0
    if os.path.exists("/tmp/target_stage_id.txt"):
        with open("/tmp/target_stage_id.txt", "r") as f:
            target_id = int(f.read().strip())

    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # If we have a specific ID, check it directly
    if target_id:
        data = models.execute_kw(db, uid, password, 'quality.alert.stage', 'read', 
            [[target_id], ['name', 'fold', 'write_date']])
        if data:
            record = data[0]
            result["stage_exists"] = True
            result["fold_state"] = record.get('fold', False)
            result["stage_name"] = record.get('name', '')
            result["write_date"] = record.get('write_date', '')
    else:
        # Fallback search by name if ID file missing
        ids = models.execute_kw(db, uid, password, 'quality.alert.stage', 'search', 
            [[['name', '=', 'Done']]])
        if ids:
            data = models.execute_kw(db, uid, password, 'quality.alert.stage', 'read', 
                [[ids[0]], ['name', 'fold', 'write_date']])
            if data:
                record = data[0]
                result["stage_exists"] = True
                result["fold_state"] = record.get('fold', False)
                result["stage_name"] = record.get('name', '')
                result["write_date"] = record.get('write_date', '')

except Exception as e:
    result["error"] = str(e)
    print(f"Error querying Odoo: {e}", file=sys.stderr)

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYTHON_EOF

# Adjust permissions for export
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="