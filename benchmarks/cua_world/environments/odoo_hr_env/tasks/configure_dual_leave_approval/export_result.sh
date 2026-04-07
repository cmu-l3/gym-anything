#!/bin/bash
echo "=== Exporting Configure Dual Leave Approval Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# -------------------------------------------------------
# Step 1: Query Current Database State via XML-RPC
# -------------------------------------------------------
echo "Querying database for final state..."
python3 << PYTHON_EOF
import xmlrpc.client
import sys
import json
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "leave_type_found": False,
    "current_validation_type": None,
    "current_responsible_ids": [],
    "write_date_timestamp": 0,
    "mitchell_admin_id": 2
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Fetch "Training Time Off"
    # We need 'write_date' to verify the agent actually modified it
    data = models.execute_kw(db, uid, password, 'hr.leave.type', 'search_read',
                             [[['name', '=', 'Training Time Off']]],
                             {'fields': ['id', 'leave_validation_type', 'responsible_ids', 'write_date']})

    if data:
        record = data[0]
        result["leave_type_found"] = True
        result["current_validation_type"] = record.get('leave_validation_type')
        result["current_responsible_ids"] = record.get('responsible_ids', [])

        # Parse write_date (format: "YYYY-MM-DD HH:MM:SS")
        write_date_str = record.get('write_date', '')
        if write_date_str:
            # Odoo returns UTC strings
            dt = datetime.datetime.strptime(write_date_str, "%Y-%m-%d %H:%M:%S")
            # Convert to unix timestamp (assuming UTC)
            result["write_date_timestamp"] = int(dt.replace(tzinfo=datetime.timezone.utc).timestamp())

except Exception as e:
    result["error"] = str(e)

# Save result to temp file
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYTHON_EOF

# -------------------------------------------------------
# Step 2: Finalize Export
# -------------------------------------------------------

# Move result to accessible location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported result:"
cat /tmp/task_result.json
echo "=== Export complete ==="