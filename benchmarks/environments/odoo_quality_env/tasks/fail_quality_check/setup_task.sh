#!/bin/bash
echo "=== Setting up fail_quality_check task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "fail_quality_check"

# Ensure the quality check exists in pending/none state
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_quality'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    ids = models.execute_kw(db, uid, 'admin', 'quality.check', 'search',
                             [[['name', '=', 'Dimension Verification - Screen Width']]])
    if ids:
        # Reset to 'none' state with empty note for clean start
        models.execute_kw(db, uid, 'admin', 'quality.check', 'write',
                          [ids, {'quality_state': 'none', 'note': ''}])
        print(f"Reset 'Dimension Verification - Screen Width' to state=none (ids={ids})")
    else:
        # Re-create if not found
        prod_ids = models.execute_kw(db, uid, 'admin', 'product.product', 'search',
                                      [[['name', 'ilike', 'Acoustic Bloc Screens']]])
        product_id = prod_ids[0] if prod_ids else None

        check_data = {
            'name': 'Dimension Verification - Screen Width',
            'quality_state': 'none',
        }
        if product_id:
            check_data['product_id'] = product_id

        try:
            check_id = models.execute_kw(db, uid, 'admin', 'quality.check', 'create', [check_data])
            print(f"Created 'Dimension Verification - Screen Width' quality check (id={check_id})")
        except Exception as e2:
            print(f"Warning creating check: {e2}", file=sys.stderr)

except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Quality Checks list view
ensure_firefox
sleep 2
navigate_firefox "http://localhost:8069/web#action=quality.action_quality_check_tree"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Quality Checks list with 'Dimension Verification - Screen Width' in open state."
echo "Agent should open the check, mark as Fail, and add failure note."
echo "=== fail_quality_check task setup complete ==="
