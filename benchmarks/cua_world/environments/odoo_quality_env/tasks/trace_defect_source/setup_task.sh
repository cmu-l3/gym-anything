#!/bin/bash
set -e
echo "=== Setting up trace_defect_source task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary data via Python
# We use a heredoc to run the Python script inside the container
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

url = "http://localhost:8069"
db = "odoo_quality"
username = "admin"
password = "admin"

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Failed to authenticate")
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # 1. Get/Create Product (Office Chair)
    product_ids = models.execute_kw(db, uid, password, 'product.product', 'search', 
        [[['name', 'ilike', 'Office Chair']]])
    if not product_ids:
        # Create if missing
        product_id = models.execute_kw(db, uid, password, 'product.product', 'create', 
            [{'name': 'Office Chair', 'type': 'product'}])
        print(f"Created product Office Chair: {product_id}")
    else:
        product_id = product_ids[0]
        print(f"Found product Office Chair: {product_id}")

    # 2. Get Picking Type (Incoming/Receipts)
    picking_type_ids = models.execute_kw(db, uid, password, 'stock.picking.type', 'search',
        [[['code', '=', 'incoming']]])
    if not picking_type_ids:
        print("Error: No incoming picking type found")
        sys.exit(1)
    picking_type_id = picking_type_ids[0]

    # 3. Get Locations
    supplier_locs = models.execute_kw(db, uid, password, 'stock.location', 'search',
        [[['usage', '=', 'supplier']]])
    supplier_loc_id = supplier_locs[0] if supplier_locs else 1
    
    stock_locs = models.execute_kw(db, uid, password, 'stock.location', 'search',
        [[['usage', '=', 'internal']]])
    stock_loc_id = stock_locs[0] if stock_locs else 1

    # 4. Create the Source Picking (Receipt for PO998877) if not exists
    existing_picking = models.execute_kw(db, uid, password, 'stock.picking', 'search',
        [[['origin', '=', 'PO998877']]])
    
    if not existing_picking:
        picking_vals = {
            'picking_type_id': picking_type_id,
            'location_id': supplier_loc_id,
            'location_dest_id': stock_loc_id,
            'origin': 'PO998877',
            'move_ids_without_package': [(0, 0, {
                'name': 'Office Chair',
                'product_id': product_id,
                'product_uom_qty': 10.0,
                'location_id': supplier_loc_id,
                'location_dest_id': stock_loc_id,
            })]
        }
        picking_id = models.execute_kw(db, uid, password, 'stock.picking', 'create', [picking_vals])
        
        # Confirm and Validate (set to Done)
        models.execute_kw(db, uid, password, 'stock.picking', 'action_confirm', [[picking_id]])
        models.execute_kw(db, uid, password, 'stock.picking', 'button_validate', [[picking_id]])
        
        picking_data = models.execute_kw(db, uid, password, 'stock.picking', 'read', [[picking_id], ['name']])
        print(f"Created Picking: {picking_data[0]['name']} (Origin: PO998877)")
    else:
        print("Picking for PO998877 already exists.")

    # 5. Create/Reset the Orphaned Quality Alert
    existing_alert = models.execute_kw(db, uid, password, 'quality.alert', 'search',
        [[['name', '=', 'Defective Office Chair']]])
        
    if not existing_alert:
        # Get product template ID (required for alert)
        prod_data = models.execute_kw(db, uid, password, 'product.product', 'read', [product_id], ['product_tmpl_id'])
        tmpl_id = prod_data[0]['product_tmpl_id'][0]

        alert_vals = {
            'name': 'Defective Office Chair',
            'product_id': product_id,
            'product_tmpl_id': tmpl_id,
            'description': 'Customer reported wobbly legs. Need to trace to source shipment.',
            'priority': '0', # Low/Normal initially
            'picking_id': False # Intentionally empty
        }
        alert_id = models.execute_kw(db, uid, password, 'quality.alert', 'create', [alert_vals])
        print(f"Created Alert: Defective Office Chair (ID: {alert_id})")
    else:
        # Reset state if it exists to ensure clean start
        models.execute_kw(db, uid, password, 'quality.alert', 'write', 
            [existing_alert, {'picking_id': False, 'priority': '0'}])
        print(f"Reset existing alert: {existing_alert}")

except Exception as e:
    print(f"Setup Error: {e}")
    sys.exit(1)
PYEOF

# Ensure Firefox is ready and navigate to Quality Alerts
# We use the generic ensure_firefox from task_utils which handles the profile/lock logic
ensure_firefox "http://localhost:8069/web#action=quality.quality_alert_action_team"

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="