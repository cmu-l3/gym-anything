#!/bin/bash
echo "=== Setting up create_quality_alert task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "create_quality_alert"

# Remove any existing alert with the exact target name to keep task fresh
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_quality'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    existing = models.execute_kw(db, uid, 'admin', 'quality.alert', 'search',
                                 [[['name', '=', 'Surface Cracks on Batch 001']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'quality.alert', 'unlink', [existing])
        print(f"Removed existing alert 'Surface Cracks on Batch 001' (ids={existing})")
    else:
        print("No existing alert with that name — clean slate")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Quality Alerts list view
ensure_firefox
sleep 2
navigate_firefox "http://localhost:8069/web#action=quality.action_quality_alert"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Odoo Quality Alerts list view."
echo "Agent should create 'Surface Cracks on Batch 001' quality alert."
echo "=== create_quality_alert task setup complete ==="
