#!/bin/bash
# Export script for delivery_backorder_processing task

echo "=== Exporting delivery_backorder_processing results ==="

# Record task end timestamp
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check setup file
if [ ! -f /tmp/delivery_backorder_setup.json ]; then
    echo "ERROR: Setup file missing!"
    echo '{"error": "Setup file missing"}' > /tmp/task_result.json
    exit 0
fi

# Use Python to verify state via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    with open('/tmp/delivery_backorder_setup.json', 'r') as f:
        setup = json.load(f)
except Exception as e:
    print(f"Error loading setup: {e}")
    sys.exit(0)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {"error": f"Connection failed: {e}"}
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Get Original Picking Status
orig_picking_id = setup['original_picking_id']
orig_picking = execute('stock.picking', 'read', [orig_picking_id], {'fields': ['state', 'write_date', 'name', 'group_id']})[0]

# Check move lines of original picking to see quantity done
orig_moves = execute('stock.move', 'search_read', [[['picking_id', '=', orig_picking_id]]], {'fields': ['product_uom_qty', 'quantity_done', 'state']})
qty_delivered_orig = sum(m['quantity_done'] for m in orig_moves)

# Find Backorder
# Backorder usually shares the same group_id or has backorder_id set to original (depending on Odoo version/config)
# Or original picking might be the backorder_id of the new one?
# In Odoo standard: The NEW picking is the backorder. Its 'backorder_id' field points to the ORIGINAL picking.
backorders = execute('stock.picking', 'search_read', 
    [[['backorder_id', '=', orig_picking_id], ['state', '!=', 'cancel']]], 
    {'fields': ['id', 'name', 'state']})

backorder_found = False
backorder_qty = 0.0
backorder_state = "none"

if backorders:
    backorder = backorders[0]
    backorder_found = True
    backorder_state = backorder['state']
    
    # Check demand of backorder
    bo_moves = execute('stock.move', 'search_read', [[['picking_id', '=', backorder['id']]]], {'fields': ['product_uom_qty']})
    backorder_qty = sum(m['product_uom_qty'] for m in bo_moves)

# Prepare result
result = {
    "original_picking_state": orig_picking['state'],
    "original_picking_qty_done": qty_delivered_orig,
    "backorder_found": backorder_found,
    "backorder_qty_demand": backorder_qty,
    "backorder_state": backorder_state,
    "original_write_date": orig_picking['write_date'],
    "task_start_time": int(os.environ.get('TASK_START', 0)), # passed via env var or read from file
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json