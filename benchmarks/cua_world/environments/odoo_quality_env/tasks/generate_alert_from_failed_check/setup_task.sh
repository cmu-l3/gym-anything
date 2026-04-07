#!/bin/bash
set -e
echo "=== Setting up generate_alert_from_failed_check task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the specific failed check scenario via XML-RPC
# We do this to ensure a clean, known starting state regardless of previous tasks
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import time

url = "http://localhost:8069"
db = "odoo_quality"
pwd = "admin"
uid = 2  # admin uid

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, "admin", pwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Find Product 'Large Cabinet'
    prod_ids = models.execute_kw(db, uid, pwd, 'product.product', 'search', [[['name', 'ilike', 'Large Cabinet']]])
    if not prod_ids:
        # Fallback to creating if missing (unlikely in this env but safe)
        prod_id = models.execute_kw(db, uid, pwd, 'product.product', 'create', [{'name': 'Large Cabinet'}])
    else:
        prod_id = prod_ids[0]

    # 2. Find a Quality Team
    team_ids = models.execute_kw(db, uid, pwd, 'quality.alert.team', 'search', [[]], {'limit': 1})
    team_id = team_ids[0] if team_ids else False
    if not team_id:
         team_id = models.execute_kw(db, uid, pwd, 'quality.alert.team', 'create', [{'name': 'Main Quality Team'}])

    # 3. Create a Failed Quality Check
    # We create a standalone check (not linked to picking) for simplicity, 
    # but with a Pass/Fail test type.
    
    # Try to find a 'passfail' test type
    test_type_id = False
    try:
        types = models.execute_kw(db, uid, pwd, 'quality.check.type', 'search', [[['technical_name', '=', 'passfail']]])
        if types:
            test_type_id = types[0]
    except:
        pass # Odoo version dependent

    vals = {
        'product_id': prod_id,
        'team_id': team_id,
        'quality_state': 'fail',
        'note': 'Setup: Automated failure for task scenario.',
    }
    if test_type_id:
        vals['test_type_id'] = test_type_id

    check_id = models.execute_kw(db, uid, pwd, 'quality.check', 'create', [vals])
    print(f"Created failed check ID: {check_id}")

    # 4. Save the ID for the export script to verify against
    with open('/tmp/target_check_id.txt', 'w') as f:
        f.write(str(check_id))

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is open and logged in
ensure_firefox "http://localhost:8069/web"

# Navigate specifically to Quality Checks to help the agent start
# (The task description says "Navigate to...", but starting them nearby is fair game for a 'medium' task 
# or we can leave them at dashboard. Let's leave them at dashboard as per description "Log in... Navigate to...")
navigate_firefox "http://localhost:8069/web#action=quality_control.quality_check_action_main"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="