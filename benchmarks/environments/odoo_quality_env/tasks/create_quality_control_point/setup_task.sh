#!/bin/bash
echo "=== Setting up create_quality_control_point task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "create_quality_control_point"

# Remove any existing QCP with the exact target name to ensure a clean start
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_quality'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    existing = models.execute_kw(db, uid, 'admin', 'quality.point', 'search',
                                 [[['name', '=', 'Cabinet Assembly Alignment Check']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'quality.point', 'unlink', [existing])
        print(f"Removed existing QCP 'Cabinet Assembly Alignment Check' (ids={existing})")
    else:
        print("No existing QCP found with that name — clean slate")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate Firefox to Quality > Configuration > Control Points
ensure_firefox
sleep 2

# Try navigating to the Configuration > Control Points menu via URL
# Odoo 17 may use legacy action URL
navigate_firefox "http://localhost:8069/web#action=quality.action_quality_point"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Odoo Quality > Control Points list view."
echo "Agent should create 'Cabinet Assembly Alignment Check' QCP."
echo "=== create_quality_control_point task setup complete ==="
