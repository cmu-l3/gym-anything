#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for verification data
echo "Extracting verification data from Odoo..."
cat << 'PYEOF' > /tmp/extract_data.py
import xmlrpc.client
import json

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid = common.authenticate(db, 'admin', password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

result = {
    "batch_feature_enabled": False,
    "pickings": {},
    "batches": []
}

try:
    # Check if Batch Transfers feature is enabled
    # The group XML ID is stock.group_stock_picking_batch
    user_data = execute('res.users', 'read', [[uid]], {'fields': ['groups_id']})
    if user_data:
        groups = execute('res.groups', 'search_read', [[['id', 'in', user_data[0]['groups_id']]]], {'fields': ['name']})
        for g in groups:
            if 'Batch Transfers' in g['name']:
                result["batch_feature_enabled"] = True
                break

    # Get the state of Delivery Orders (pickings) for our specific customers
    customers = [
        "Downtown Commercial HVAC",
        "City Metro Transit Authority",
        "Apex Construction",
        "Riverside Property Management",
        "Toronto Industrial Corp",
        "London Underground Maintenance"
    ]
    
    for c in customers:
        pickings = execute('stock.picking', 'search_read', 
                           [[['partner_id.name', '=', c], ['picking_type_id.code', '=', 'outgoing']]], 
                           {'fields': ['id', 'name', 'state', 'batch_id']})
        if pickings:
            p = pickings[0]
            result["pickings"][c] = {
                "picking_id": p["id"],
                "name": p["name"],
                "state": p["state"],
                "batch_id": p["batch_id"][0] if p["batch_id"] else None,
                "batch_name": p["batch_id"][1] if p["batch_id"] else None
            }

    # Get all batches created
    batches = execute('stock.picking.batch', 'search_read', [[]], {'fields': ['id', 'name', 'state', 'picking_ids']})
    result["batches"] = batches

except Exception as e:
    result["error"] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
PYEOF

python3 /tmp/extract_data.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "Result JSON written:"
cat /tmp/task_result.json
echo "=== Export Complete ==="