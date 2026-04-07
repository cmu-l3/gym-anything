#!/bin/bash
set -e
echo "=== Setting up Configure Dual Leave Approval Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# -------------------------------------------------------
# Step 1: Reset "Training Time Off" to a known initial state
# State: Approval = "By Employee's Approver" (manager), Responsible = None
# -------------------------------------------------------
echo "Resetting leave type configuration via XML-RPC..."
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import json

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find "Training Time Off"
    leave_types = models.execute_kw(db, uid, password, 'hr.leave.type', 'search_read',
                                    [[['name', '=', 'Training Time Off']]],
                                    {'fields': ['id', 'name', 'leave_validation_type', 'responsible_ids']})

    if not leave_types:
        print("ERROR: 'Training Time Off' leave type not found!", file=sys.stderr)
        sys.exit(1)

    leave_type_id = leave_types[0]['id']
    print(f"Found Leave Type ID: {leave_type_id}")

    # Reset to Single Approval ('manager') and Clear Responsible
    # leave_validation_type: 'no_validation', 'manager', 'hr', 'both'
    models.execute_kw(db, uid, password, 'hr.leave.type', 'write',
                      [[leave_type_id], {
                          'leave_validation_type': 'manager',
                          'responsible_ids': [[6, 0, []]]  # Clear many2many
                      }])

    print("Successfully reset 'Training Time Off' to initial state.")

    # Record initial state to file for verifier comparison
    initial_state = {
        "id": leave_type_id,
        "leave_validation_type": "manager",
        "responsible_ids": []
    }
    with open('/tmp/initial_leave_config.json', 'w') as f:
        json.dump(initial_state, f)

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# -------------------------------------------------------
# Step 2: Prepare Application State
# -------------------------------------------------------

# Launch Firefox and navigate directly to the Time Off Types list
# This puts the agent in the right context but requires them to find the specific record
echo "Launching Firefox..."
ensure_firefox "http://localhost:8069/web#action=hr_holidays.hr_leave_type_action"

# Wait for page load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="