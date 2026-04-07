#!/bin/bash
# Setup script for inventory_scrap_processing task
# Creates 3 products, sets initial stock, and generates the damage report file.

echo "=== Setting up inventory_scrap_processing ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Python script to set up Odoo data
python3 << 'PYEOF'
import xmlrpc.client
import sys

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

# 1. Products to create
products_data = [
    {
        "name": "Industrial Safety Helmet - Class E",
        "type": "product",
        "standard_price": 42.00,
        "list_price": 55.00,
        "initial_qty": 120
    },
    {
        "name": "Heavy Duty Pallet Jack - 5500lb",
        "type": "product",
        "standard_price": 389.00,
        "list_price": 550.00,
        "initial_qty": 18
    },
    {
        "name": "Corrugated Shipping Box - 24x18x12",
        "type": "product",
        "standard_price": 3.75,
        "list_price": 5.00,
        "initial_qty": 500
    }
]

# 2. Find internal stock location (WH/Stock)
locations = execute('stock.location', 'search_read',
    [[['usage', '=', 'internal'], ['complete_name', 'ilike', 'WH/Stock']]],
    {'fields': ['id', 'complete_name'], 'limit': 1})

if not locations:
    # Fallback to any internal location
    locations = execute('stock.location', 'search_read',
        [[['usage', '=', 'internal']]],
        {'fields': ['id', 'complete_name'], 'limit': 1})

if not locations:
    print("ERROR: No internal stock location found", file=sys.stderr)
    sys.exit(1)

location_id = locations[0]['id']
print(f"Using location: {locations[0]['complete_name']} (id={location_id})")

# 3. Create products and set inventory
created_ids = {}

for p_data in products_data:
    # Check if exists
    existing = execute('product.product', 'search_read',
        [[['name', '=', p_data['name']]]],
        {'fields': ['id']})
    
    if existing:
        product_id = existing[0]['id']
        print(f"Using existing product: {p_data['name']}")
    else:
        product_id = execute('product.product', 'create', [{
            'name': p_data['name'],
            'type': p_data['type'],
            'standard_price': p_data['standard_price'],
            'list_price': p_data['list_price']
        }])
        print(f"Created product: {p_data['name']}")

    created_ids[p_data['name']] = product_id

    # Set inventory quantity (using stock.quant)
    # Check existing quant
    quants = execute('stock.quant', 'search_read',
        [[['product_id', '=', product_id], ['location_id', '=', location_id]]],
        {'fields': ['id', 'quantity']})
    
    current_qty = quants[0]['quantity'] if quants else 0.0
    
    if current_qty != p_data['initial_qty']:
        # Create or update quant
        # Note: In Odoo 14+, typically we use inventory_quantity and action_apply_inventory
        # But for setup, we can often force it or use a stock change wizard. 
        # Using simple stock.quant create/write for simplicity if allowed in context.
        # If not, we use stock.change.product.qty wizard.
        
        try:
            # Try stock.change.product.qty wizard method (most reliable across versions)
            wizard_id = execute('stock.change.product.qty', 'create', [{
                'product_id': product_id,
                'new_quantity': p_data['initial_qty'],
                'product_tmpl_id': execute('product.product', 'read', [product_id], ['product_tmpl_id'])[0]['product_tmpl_id'][0]
            }])
            execute('stock.change.product.qty', 'change_product_qty', [wizard_id])
            print(f"Set quantity for {p_data['name']} to {p_data['initial_qty']}")
        except Exception as e:
            print(f"Method 1 failed ({e}), trying direct quant creation...")
            # Fallback: direct quant creation (often works in demo/test envs)
            execute('stock.quant', 'create', [{
                'product_id': product_id,
                'location_id': location_id,
                'quantity': p_data['initial_qty']
            }])

# 4. Record initial scrap count
scrap_count = execute('stock.scrap', 'search_count', [[]])
with open('/tmp/initial_scrap_count.txt', 'w') as f:
    f.write(str(scrap_count))

PYEOF

# Create the damage assessment report on Desktop
cat > /home/ga/Desktop/damage_assessment_report.txt << 'EOF'
============================================
  WAREHOUSE DAMAGE ASSESSMENT REPORT
============================================
Date: 2024-10-24
Incident: Forklift collision in Aisle 7, Bay C
Inspector: M. Chen, Loss Prevention
Incident Ref: WH-DMG-2024-0847

SUMMARY OF DAMAGED INVENTORY
--------------------------------------------

1. Industrial Safety Helmet - Class E
   Quantity Destroyed: 25 units
   Cause: Crushed by falling pallet during collision
   Condition: Non-recoverable, structural integrity compromised

2. Heavy Duty Pallet Jack - 5500lb
   Quantity Damaged: 4 units
   Cause: Direct forklift impact; hydraulic systems ruptured
   Condition: Beyond economical repair

3. Corrugated Shipping Box - 24x18x12
   Quantity Damaged: 85 units
   Cause: Water damage from sprinkler activation post-collision
   Condition: Saturated/collapsed, unusable

ACTION REQUIRED:
All items listed above must be removed from available
inventory via scrap orders in the ERP system.

Scrap Location: Virtual Locations / Scrap
============================================
EOF

# Ensure report ownership
chown ga:ga /home/ga/Desktop/damage_assessment_report.txt

# Start Firefox with Odoo
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Wait for window and maximize
wait_for_window "firefox\|mozilla\|Odoo" 30
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="