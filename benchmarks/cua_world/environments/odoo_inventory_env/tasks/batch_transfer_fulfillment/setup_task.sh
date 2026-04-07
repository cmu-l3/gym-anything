#!/bin/bash
echo "=== Setting up Batch Transfer Fulfillment Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time

# Start and wait for Odoo
cd /home/ga/odoo
docker-compose up -d 2>/dev/null || true

echo "Waiting for Odoo to be ready..."
for i in {1..60}; do
    if curl -s http://localhost:8069/web/login > /dev/null; then
        break
    fi
    sleep 2
done

# Execute Python script to seed the initial database state
echo "Seeding Odoo database with customers, products, stock, and delivery orders..."
cat << 'PYEOF' | python3
import xmlrpc.client
import time

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid = common.authenticate(db, 'admin', password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

try:
    # 1. Disable Batch Transfers initially
    settings_id = execute('res.config.settings', 'create', [{'group_stock_picking_batch': False}])
    execute('res.config.settings', 'execute', [[settings_id]])
    print("Batch Transfers disabled in settings.")

    # 2. Get Locations and Picking Types
    wh = execute('stock.warehouse', 'search_read', [[]], {'fields': ['lot_stock_id'], 'limit': 1})
    stock_loc_id = wh[0]['lot_stock_id'][0]
    
    cust_loc = execute('stock.location', 'search_read', [[['usage', '=', 'customer']]], {'fields': ['id'], 'limit': 1})
    customer_loc_id = cust_loc[0]['id']
    
    pick_type = execute('stock.picking.type', 'search_read', [[['code', '=', 'outgoing']]], {'fields': ['id'], 'limit': 1})
    out_pick_type_id = pick_type[0]['id']

    # 3. Create Customers
    customers = [
        "Downtown Commercial HVAC",
        "City Metro Transit Authority",
        "Apex Construction",
        "Riverside Property Management",
        "Toronto Industrial Corp",
        "London Underground Maintenance"
    ]
    partner_ids = {}
    for c in customers:
        p_id = execute('res.partner', 'create', [{'name': c}])
        partner_ids[c] = p_id

    # 4. Create Products and add stock
    products = [
        "Klein Tools 32500 11-in-1 Multi-Bit Screwdriver",
        "Fluke 117 Electrician's True RMS Multimeter",
        "Knipex Cobra Water Pump Pliers (87 01 250)",
        "Milwaukee Fastback Folding Utility Knife (48-22-1502)"
    ]
    
    uom = execute('uom.uom', 'search_read', [[['name', '=', 'Units']]], {'fields': ['id'], 'limit': 1})
    uom_id = uom[0]['id'] if uom else 1

    prod_ids = []
    for idx, p in enumerate(products):
        p_tmpl_id = execute('product.template', 'create', [{
            'name': p,
            'type': 'product',
        }])
        p_obj = execute('product.product', 'search_read', [[['product_tmpl_id', '=', p_tmpl_id]]], {'fields': ['id'], 'limit': 1})
        p_id = p_obj[0]['id']
        prod_ids.append(p_id)
        
        # Add Stock
        quant_id = execute('stock.quant', 'create', [{
            'product_id': p_id,
            'location_id': stock_loc_id,
            'inventory_quantity': 500
        }])
        execute('stock.quant', 'action_apply_inventory', [[quant_id]])

    # 5. Create Delivery Orders for each customer
    for i, c in enumerate(customers):
        pick_id = execute('stock.picking', 'create', [{
            'partner_id': partner_ids[c],
            'picking_type_id': out_pick_type_id,
            'location_id': stock_loc_id,
            'location_dest_id': customer_loc_id,
        }])
        
        # Add a couple of random items to each order
        execute('stock.move', 'create', [{
            'name': 'Move 1',
            'picking_id': pick_id,
            'product_id': prod_ids[i % 4],
            'product_uom_qty': 5,
            'product_uom': uom_id,
            'location_id': stock_loc_id,
            'location_dest_id': customer_loc_id,
        }])
        execute('stock.move', 'create', [{
            'name': 'Move 2',
            'picking_id': pick_id,
            'product_id': prod_ids[(i + 1) % 4],
            'product_uom_qty': 3,
            'product_uom': uom_id,
            'location_id': stock_loc_id,
            'location_dest_id': customer_loc_id,
        }])
        
        # Confirm and Assign (Reserve stock) so they appear as 'Ready'
        execute('stock.picking', 'action_confirm', [[pick_id]])
        execute('stock.picking', 'action_assign', [[pick_id]])

    print("Data seeded successfully.")
except Exception as e:
    print(f"Error seeding database: {e}")
PYEOF

# Ensure Firefox is running and focused on Odoo
echo "Starting Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' > /dev/null 2>&1 &"
    sleep 5
fi

# Maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="