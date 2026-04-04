#!/bin/bash
echo "=== Setting up set_control_point_failure_message task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "set_control_point_failure_message"

# Reset the QCP to have empty failure_message for clean start
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_quality'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    ids = models.execute_kw(db, uid, 'admin', 'quality.point', 'search',
                             [[['name', '=', 'Incoming Parts Verification']]])
    if ids:
        # Reset failure_message to empty for clean start
        try:
            models.execute_kw(db, uid, 'admin', 'quality.point', 'write',
                              [ids, {'failure_message': ''}])
            print(f"Reset failure_message on 'Incoming Parts Verification' (ids={ids})")
        except Exception as e2:
            print(f"Note: Could not reset failure_message (field may not exist): {e2}", file=sys.stderr)
    else:
        # Re-create if not found
        prod_ids = models.execute_kw(db, uid, 'admin', 'product.product', 'search',
                                      [[['name', 'ilike', 'Cabinet with Doors']]])
        product_id = prod_ids[0] if prod_ids else None

        picking_type_ids = models.execute_kw(db, uid, 'admin', 'stock.picking.type', 'search',
                                              [[['code', '=', 'incoming']]])
        picking_type_id = picking_type_ids[0] if picking_type_ids else None

        qcp_data = {
            'name': 'Incoming Parts Verification',
            'note': 'Verify all incoming parts meet dimensional and finish specifications.',
        }
        if product_id:
            qcp_data['product_ids'] = [product_id]
        if picking_type_id:
            qcp_data['picking_type_ids'] = [picking_type_id]

        try:
            qcp_id = models.execute_kw(db, uid, 'admin', 'quality.point', 'create', [qcp_data])
            print(f"Created 'Incoming Parts Verification' QCP (id={qcp_id})")
        except Exception as e2:
            qcp_data.pop('product_ids', None)
            qcp_data.pop('picking_type_ids', None)
            qcp_id = models.execute_kw(db, uid, 'admin', 'quality.point', 'create', [qcp_data])
            print(f"Created minimal QCP (id={qcp_id}): {e2}")

except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Quality > Configuration > Control Points
ensure_firefox
sleep 2
navigate_firefox "http://localhost:8069/web#action=quality.action_quality_point"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Quality Control Points list with 'Incoming Parts Verification'."
echo "Agent should open the QCP and set the failure message."
echo "=== set_control_point_failure_message task setup complete ==="
