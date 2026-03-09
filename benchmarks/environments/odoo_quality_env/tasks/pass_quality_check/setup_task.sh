#!/bin/bash
echo "=== Setting up pass_quality_check task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "pass_quality_check"

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
                             [[['name', '=', 'Visual Inspection - Cabinet Finish']]])
    if ids:
        # Reset to 'none' state for clean start
        models.execute_kw(db, uid, 'admin', 'quality.check', 'write',
                          [ids, {'quality_state': 'none'}])
        print(f"Reset 'Visual Inspection - Cabinet Finish' to state=none (ids={ids})")
    else:
        # Re-create if not found
        prod_ids = models.execute_kw(db, uid, 'admin', 'product.product', 'search',
                                      [[['name', 'ilike', 'Cabinet with Doors']]])
        product_id = prod_ids[0] if prod_ids else None

        # Find a quality control point to link to (if any)
        point_ids = models.execute_kw(db, uid, 'admin', 'quality.point', 'search',
                                       [[['name', '=', 'Incoming Parts Verification']]])
        point_id = point_ids[0] if point_ids else None

        check_data = {
            'name': 'Visual Inspection - Cabinet Finish',
            'quality_state': 'none',
        }
        if product_id:
            check_data['product_id'] = product_id
        if point_id:
            check_data['point_id'] = point_id

        try:
            check_id = models.execute_kw(db, uid, 'admin', 'quality.check', 'create', [check_data])
            print(f"Created 'Visual Inspection - Cabinet Finish' quality check (id={check_id})")
        except Exception as e2:
            # Try without point_id
            check_data.pop('point_id', None)
            check_id = models.execute_kw(db, uid, 'admin', 'quality.check', 'create', [check_data])
            print(f"Created quality check without QCP (id={check_id}): {e2}")

except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Quality Checks list view
ensure_firefox
sleep 2
navigate_firefox "http://localhost:8069/web#action=quality.action_quality_check_tree"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Quality Checks list with 'Visual Inspection - Cabinet Finish' in open state."
echo "Agent should open the check and mark it as Pass."
echo "=== pass_quality_check task setup complete ==="
