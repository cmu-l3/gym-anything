#!/bin/bash
echo "=== Setting up add_corrective_action task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "add_corrective_action"

# Reset the target alert to have empty corrective_action for clean start
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_quality'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    ids = models.execute_kw(db, uid, 'admin', 'quality.alert', 'search',
                             [[['name', '=', 'Incorrect Spacing Between Components']]])
    if ids:
        # Ensure corrective_action is empty (clean start)
        models.execute_kw(db, uid, 'admin', 'quality.alert', 'write',
                          [ids, {'corrective_action': '', 'preventive_action': ''}])
        print(f"Reset corrective_action on 'Incorrect Spacing Between Components' (ids={ids})")
    else:
        # Re-create if not found
        prod_ids = models.execute_kw(db, uid, 'admin', 'product.product', 'search',
                                      [[['name', 'ilike', 'Cabinet with Doors']]])
        product_id = prod_ids[0] if prod_ids else None
        stages = models.execute_kw(db, uid, 'admin', 'quality.alert.stage', 'search_read',
                                    [[]], {'fields': ['id', 'name']})
        new_stage_id = stages[0]['id'] if stages else None
        alert_data = {
            'name': 'Incorrect Spacing Between Components',
            'description': 'Assembly inspection found spacing between components is 3mm larger than specification. This affects product stability and assembly alignment.',
            'priority': '0',
            'corrective_action': '',
            'preventive_action': '',
        }
        if product_id:
            alert_data['product_id'] = product_id
        if new_stage_id:
            alert_data['stage_id'] = new_stage_id
        new_id = models.execute_kw(db, uid, 'admin', 'quality.alert', 'create', [alert_data])
        print(f"Created 'Incorrect Spacing Between Components' alert (id={new_id})")

except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Quality Alerts list view
ensure_firefox
sleep 2
navigate_firefox "http://localhost:8069/web#action=quality.action_quality_alert"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Quality Alerts list with 'Incorrect Spacing Between Components'."
echo "Agent should open the alert and add the specified corrective action text."
echo "=== add_corrective_action task setup complete ==="
