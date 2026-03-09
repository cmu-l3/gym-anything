#!/bin/bash
echo "=== Setting up set_alert_priority task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "set_alert_priority"

# Reset the target alert to Normal priority (0 stars) for clean start
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_quality'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    ids = models.execute_kw(db, uid, 'admin', 'quality.alert', 'search',
                             [[['name', '=', 'Critical Weld Failure on Frame']]])
    if ids:
        models.execute_kw(db, uid, 'admin', 'quality.alert', 'write',
                          [ids, {'priority': '0'}])
        print(f"Reset priority to Normal on 'Critical Weld Failure on Frame' (ids={ids})")
    else:
        # Re-create if not found
        prod_ids = models.execute_kw(db, uid, 'admin', 'product.product', 'search',
                                      [[['name', 'ilike', 'Cabinet with Doors']]])
        product_id = prod_ids[0] if prod_ids else None
        stages = models.execute_kw(db, uid, 'admin', 'quality.alert.stage', 'search_read',
                                    [[]], {'fields': ['id', 'name']})
        new_stage_id = stages[0]['id'] if stages else None
        alert_data = {
            'name': 'Critical Weld Failure on Frame',
            'description': 'Weld joint on main frame found to have micro-cracks. Structural integrity compromised. Immediate inspection required for all units from same production run.',
            'priority': '0',  # Normal — task will set this to High
        }
        if product_id:
            alert_data['product_id'] = product_id
        if new_stage_id:
            alert_data['stage_id'] = new_stage_id
        new_id = models.execute_kw(db, uid, 'admin', 'quality.alert', 'create', [alert_data])
        print(f"Created 'Critical Weld Failure on Frame' alert (id={new_id})")

except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Quality Alerts list view
ensure_firefox
sleep 2
navigate_firefox "http://localhost:8069/web#action=quality.action_quality_alert"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Quality Alerts list with 'Critical Weld Failure on Frame' at Normal priority."
echo "Agent should open the alert and set priority to High (1 star)."
echo "=== set_alert_priority task setup complete ==="
