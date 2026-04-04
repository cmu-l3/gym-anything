#!/bin/bash
echo "=== Setting up close_quality_alert task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "close_quality_alert"

# Re-create the target alert in "New" stage to ensure deterministic start state
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_quality'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find the New stage
    stages = models.execute_kw(db, uid, 'admin', 'quality.alert.stage', 'search_read',
                                [[]], {'fields': ['id', 'name']})
    new_stage_id = None
    first_stage_id = stages[0]['id'] if stages else None
    for s in stages:
        if 'new' in s['name'].lower() or 'open' in s['name'].lower():
            new_stage_id = s['id']
            break
    if not new_stage_id:
        new_stage_id = first_stage_id
    print(f"Using New stage id={new_stage_id}")

    # Find product (Cabinet with Doors)
    prod_ids = models.execute_kw(db, uid, 'admin', 'product.product', 'search',
                                  [[['name', 'ilike', 'Cabinet with Doors']]])
    product_id = prod_ids[0] if prod_ids else None

    # Remove existing alert with this name
    existing = models.execute_kw(db, uid, 'admin', 'quality.alert', 'search',
                                  [[['name', '=', 'Paint Discoloration on Metal Panels']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'quality.alert', 'unlink', [existing])
        print("Removed stale alert")

    # Create fresh alert in New stage
    alert_data = {
        'name': 'Paint Discoloration on Metal Panels',
        'description': 'Multiple units from Batch BATCH-2024-003 show discoloration and uneven paint coverage on metal panel surfaces. Affected 12 out of 50 units inspected.',
        'priority': '0',
    }
    if product_id:
        alert_data['product_id'] = product_id
    if new_stage_id:
        alert_data['stage_id'] = new_stage_id

    alert_id = models.execute_kw(db, uid, 'admin', 'quality.alert', 'create', [alert_data])
    print(f"Created fresh alert 'Paint Discoloration on Metal Panels' in New stage (id={alert_id})")

except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Quality Alerts list view
ensure_firefox
sleep 2
navigate_firefox "http://localhost:8069/web#action=quality.action_quality_alert"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Quality Alerts list with 'Paint Discoloration on Metal Panels' in New stage."
echo "Agent should find and close this alert (move to Done stage)."
echo "=== close_quality_alert task setup complete ==="
