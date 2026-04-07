#!/bin/bash
# Setup script for inventory_supply_chain_traceability task
# Creates a supply chain history:
# 1. Product with Lot Tracking enabled
# 2. Purchase from Vendor A (Good Lot)
# 3. Purchase from Vendor B (Bad Lot)
# 4. Delivery to Customer (Azure Interior) containing the Bad Lot
# 5. The agent must trace the delivery back to Vendor B

echo "=== Setting up Supply Chain Traceability Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for screenshots
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Execute Python setup script
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import time
import random

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    if not uid:
        print("ERROR: Authentication failed!", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Cannot connect to Odoo: {e}", file=sys.stderr)
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

print("Connected to Odoo. Starting setup...")

# 1. Enable Lots/Serial Numbers
# We need to ensure the user has the group. In Odoo 16+, this is often a setting.
# We'll try to add the group to the admin user directly to be safe.
try:
    group_lot = execute('ir.model.data', 'get_object_reference', ['stock', 'group_stock_production_lot'])[1]
    execute('res.users', 'write', [[uid], {'groups_id': [(4, group_lot)]}])
    print("Enabled Lot/Serial Number tracking group for admin.")
except Exception as e:
    print(f"Warning: Could not enable lot group (might already be active): {e}")

# 2. Create Product (Tracked by Lots)
product_id = execute('product.product', 'create', [{
    'name': 'Ergonomic Mesh Chair',
    'type': 'product',  # Storable
    'tracking': 'lot',  # Track by lots
    'list_price': 350.00,
    'standard_price': 150.00,
}])
print(f"Created Product: Ergonomic Mesh Chair (ID: {product_id})")

# 3. Create Vendors
vendor_a_id = execute('res.partner', 'create', [{
    'name': 'SafeSeat Supply',
    'is_company': True,
    'supplier_rank': 1
}])
vendor_b_id = execute('res.partner', 'create', [{
    'name': 'Budget Office Imports',
    'is_company': True,
    'supplier_rank': 1
}])
print(f"Created Vendors: SafeSeat Supply ({vendor_a_id}), Budget Office Imports ({vendor_b_id})")

# 4. Create Customer
customer_id = execute('res.partner', 'create', [{
    'name': 'Azure Interior',
    'is_company': True,
    'customer_rank': 1
}])
print(f"Created Customer: Azure Interior ({customer_id})")

# 5. Purchase Good Stock (Vendor A)
# PO -> Confirm -> Receipt -> Assign Lot -> Validate
po_a_id = execute('purchase.order', 'create', [{
    'partner_id': vendor_a_id,
    'order_line': [(0, 0, {
        'product_id': product_id,
        'product_qty': 10,
        'price_unit': 160.00,
    })]
}])
execute('purchase.order', 'button_confirm', [[po_a_id]])
print(f"Created PO A ({po_a_id}) for Good Stock")

# Process Receipt for PO A
picking_a_id = execute('purchase.order', 'read', [po_a_id], ['picking_ids'])[0]['picking_ids'][0]

# Set Lot for Receipt A
# We need to find the move line and set the lot_name
move_ids = execute('stock.picking', 'read', [picking_a_id], ['move_ids_without_package'])[0]['move_ids_without_package']
# Create Lot first
lot_ok_id = execute('stock.production.lot', 'create', [{
    'name': 'LOT-OK-882',
    'product_id': product_id,
    'company_id': 1
}])
# Update move line with lot and qty_done
# Note: In recent Odoo versions, we update stock.move.line, not stock.move
# We need to find the specific move line linked to the move
move_line_ids = execute('stock.move', 'read', move_ids, ['move_line_ids'])[0]['move_line_ids']

if not move_line_ids:
    # If no move lines exist yet (draft), we might need to assign quantity to move first or create lines
    # Usually 'qty_done' on stock.move triggers line creation or we write to move_line_ids directly
    pass

# Simpler approach for receiving: Update the move lines directly via the picking's immediate transfer logic or manual update
# Let's try writing to move_line_ids_without_package on the picking if available, or finding the lines
move_lines = execute('stock.move.line', 'search_read', [['picking_id', '=', picking_a_id]], ['id'])
for line in move_lines:
    execute('stock.move.line', 'write', [[line['id']], {
        'lot_id': lot_ok_id,
        'qty_done': 10
    }])

execute('stock.picking', 'button_validate', [[picking_a_id]])
print("Received Good Stock (LOT-OK-882)")


# 6. Purchase BAD Stock (Vendor B) - THIS IS THE TARGET
po_b_id = execute('purchase.order', 'create', [{
    'partner_id': vendor_b_id,
    'order_line': [(0, 0, {
        'product_id': product_id,
        'product_qty': 5,
        'price_unit': 140.00,  # Cheaper!
    })]
}])
execute('purchase.order', 'button_confirm', [[po_b_id]])
po_b_name = execute('purchase.order', 'read', [po_b_id], ['name'])[0]['name']
print(f"Created PO B ({po_b_id} / {po_b_name}) for Bad Stock")

# Process Receipt for PO B
picking_b_id = execute('purchase.order', 'read', [po_b_id], ['picking_ids'])[0]['picking_ids'][0]

# Create Bad Lot
lot_def_id = execute('stock.production.lot', 'create', [{
    'name': 'LOT-DEF-991',
    'product_id': product_id,
    'company_id': 1
}])

# Update move lines for Receipt B
move_lines_b = execute('stock.move.line', 'search_read', [['picking_id', '=', picking_b_id]], ['id'])
# If lines don't exist yet (might happen if picking is just created), we might need to force assignment or check stock.move
if not move_lines_b:
    # Trigger assignment
    execute('stock.picking', 'action_assign', [[picking_b_id]])
    move_lines_b = execute('stock.move.line', 'search_read', [['picking_id', '=', picking_b_id]], ['id'])

for line in move_lines_b:
    execute('stock.move.line', 'write', [[line['id']], {
        'lot_id': lot_def_id,
        'qty_done': 5
    }])

execute('stock.picking', 'button_validate', [[picking_b_id]])
print("Received Bad Stock (LOT-DEF-991)")


# 7. Create Sales Order for Customer (The Incident)
so_id = execute('sale.order', 'create', [{
    'partner_id': customer_id,
    'order_line': [(0, 0, {
        'product_id': product_id,
        'product_qty': 1,
    })]
}])
execute('sale.order', 'action_confirm', [[so_id]])
print(f"Created Sales Order ({so_id})")

# 8. Process Delivery - FORCE SENDING THE BAD LOT
picking_out_id = execute('sale.order', 'read', [so_id], ['picking_ids'])[0]['picking_ids'][0]

# Rename the picking to ensure it matches the task description WH/OUT/00099
# This is a bit of a hack, but important for the task description to be static
# Odoo sequence numbers are automatic, but we can try to force the name or just find the name it got
# Better: Just find out what name it got and write it to the description?
# No, the task description says "WH/OUT/00099". We should try to rename it.
try:
    execute('stock.picking', 'write', [[picking_out_id], {'name': 'WH/OUT/00099'}])
    print("Renamed delivery to WH/OUT/00099")
except Exception as e:
    print(f"Could not rename picking: {e}. Fallback: verify verification script handles dynamic names if needed.")
    # If we can't rename, we might have a mismatch.
    # However, since we are the only ones creating data, it might be predictable if DB is fresh.
    # But for safety, we'll stick with writing the name. If it fails (due to sequence constraints),
    # the agent might have to search by Customer.
    # Let's update the ground truth with the actual name just in case.
    pass

final_picking_name = execute('stock.picking', 'read', [picking_out_id], ['name'])[0]['name']

# Assign the BAD LOT to the delivery
execute('stock.picking', 'action_assign', [[picking_out_id]])
move_lines_out = execute('stock.move.line', 'search_read', [['picking_id', '=', picking_out_id]], ['id', 'product_uom_qty'])

# Odoo might have auto-reserved the Good lot (FIFO). We must change it.
# We unreserve or just overwrite.
for line in move_lines_out:
    # Update to use the bad lot
    execute('stock.move.line', 'write', [[line['id']], {
        'lot_id': lot_def_id,
        'qty_done': 1
    }])

execute('stock.picking', 'button_validate', [[picking_out_id]])
print(f"Shipped Bad Stock (LOT-DEF-991) via {final_picking_name}")

# 9. Save Ground Truth
truth = {
    "target_lot": "LOT-DEF-991",
    "target_vendor": "Budget Office Imports",
    "target_po": po_b_name,
    "target_delivery": final_picking_name
}
with open('/tmp/traceability_truth.json', 'w') as f:
    json.dump(truth, f)

print("Setup Complete. Ground truth saved.")

PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is open and ready
source /workspace/scripts/task_utils.sh
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' > /dev/null 2>&1 &"
fi
wait_for_window "Odoo" 60
focus_window "Firefox"

echo "=== Task Setup Finished ==="