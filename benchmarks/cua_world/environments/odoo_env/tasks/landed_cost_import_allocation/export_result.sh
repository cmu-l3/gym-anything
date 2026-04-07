#!/bin/bash
# Export script for landed_cost_import_allocation

echo "=== Exporting Results ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to query results
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

# Load setup info
try:
    with open('/tmp/landed_cost_setup.json', 'r') as f:
        setup = json.load(f)
    target_picking_id = setup['picking_id']
except:
    target_picking_id = None

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start_time = float(f.read().strip())
except:
    task_start_time = 0

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except:
    # Fail gracefully if Odoo down
    print("Could not connect to Odoo")
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Find Landed Costs created after start time (approx check via ID or modification)
# We'll just fetch all landed costs and filter in python or check the one linked to our picking

# Search for landed costs linked to our picking
# The link is usually via 'picking_ids' (Many2many)
landed_costs = execute('stock.landed.cost', 'search_read',
    [],
    {'fields': ['id', 'state', 'picking_ids', 'cost_lines', 'amount_total', 'create_date']})

candidate = None
match_found = False

for lc in landed_costs:
    # Check if linked to our picking
    if target_picking_id and target_picking_id in lc.get('picking_ids', []):
        candidate = lc
        match_found = True
        break

result_data = {
    "found_record": False,
    "state": None,
    "picking_match": False,
    "total_amount": 0,
    "lines": [],
    "screenshot_path": "/tmp/task_final.png"
}

if candidate:
    result_data["found_record"] = True
    result_data["state"] = candidate['state']
    result_data["picking_match"] = True
    result_data["total_amount"] = candidate.get('amount_total', 0)
    
    # Get lines details
    line_ids = candidate.get('cost_lines', [])
    if line_ids:
        lines = execute('stock.landed.cost.lines', 'read', line_ids, ['name', 'price_unit', 'split_method'])
        result_data["lines"] = lines

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result_data, f, indent=2)

print("Export complete.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true