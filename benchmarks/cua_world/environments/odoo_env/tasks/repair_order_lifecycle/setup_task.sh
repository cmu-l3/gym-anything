#!/bin/bash
# Setup script for repair_order_lifecycle task
# Installs Repair module, creates Customer, Products, and ensures Stock is available.

echo "=== Setting up repair_order_lifecycle ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_timestamp

# Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Create the ticket file on Desktop
cat > /home/ga/Desktop/repair_ticket.txt << 'EOF'
REPAIR TICKET #4920
===================
Customer: Constructors Inc
Item: Industrial Power Drill
Issue: Battery not holding charge, motor check required.

Work Required:
1. Replace Battery
   - Part: High-Capacity Battery
   - Quantity: 1

2. Labor / Service
   - Service: Repair Labor
   - Duration: 2 Hours

Billing:
- Out of Warranty (Billable)
- Generate and Post Invoice upon completion
EOF
chown ga:ga /home/ga/Desktop/repair_ticket.txt

# Run Python setup via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

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

def execute(model, method, *args, **kwargs):
    return models.execute_kw(DB, uid, PASSWORD, model, method, list(args), kwargs)

# 1. Install 'repair' module if not installed
print("Checking 'repair' module...")
module = execute('ir.module.module', 'search_read', [['name', '=', 'repair']], {'fields': ['state', 'id']})
if module and module[0]['state'] != 'installed':
    print("Installing 'repair' module (this may take a moment)...")
    execute('ir.module.module', 'button_immediate_install', [module[0]['id']])
    # Wait for install to propagate (simple sleep, in real env might need retry loop for connection)
    time.sleep(10) 
    # Re-authenticate after module install (sometimes registry reloads)
    try:
        common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
        uid = common.authenticate(DB, USERNAME, PASSWORD, {})
        models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
    except:
        pass

# 2. Create Customer
print("Creating Customer...")
customer_id = execute('res.partner', 'create', {
    'name': 'Constructors Inc',
    'is_company': True,
    'email': 'service@constructors.inc',
    'phone': '555-0199'
})

# 3. Create Product to be Repaired (Industrial Power Drill)
print("Creating Drill Product...")
drill_id = execute('product.product', 'create', {
    'name': 'Industrial Power Drill',
    'detailed_type': 'product', # Storable
    'list_price': 150.00,
    'tracking': 'none', # Simplify by not requiring serial numbers for this task
})

# 4. Create Replacement Part (High-Capacity Battery)
print("Creating Battery Product...")
battery_id = execute('product.product', 'create', {
    'name': 'High-Capacity Battery',
    'detailed_type': 'product', # Storable
    'list_price': 120.00,
    'standard_price': 85.00,
})

# 5. Create Labor Service
print("Creating Labor Service...")
labor_id = execute('product.product', 'create', {
    'name': 'Repair Labor',
    'detailed_type': 'service',
    'list_price': 65.00,
    'uom_id': 1, # Default Unit (usually Hours for service in demo data, or Units)
    'uom_po_id': 1
})

# 6. Update Inventory for Battery (Prevent blocking)
# Find stock location
locs = execute('stock.location', 'search_read', [['usage', '=', 'internal']], {'limit': 1})
if locs:
    location_id = locs[0]['id']
    print(f"Updating stock in {locs[0]['name']}...")
    # Create inventory adjustment (using stock.quant directly for Odoo 16/17 simplicity)
    execute('stock.quant', 'create', {
        'product_id': battery_id,
        'location_id': location_id,
        'inventory_quantity': 50.0,
    })
    # Apply the adjustment (search for the quant we just made or all quants for this product)
    quants = execute('stock.quant', 'search', [['product_id', '=', battery_id], ['location_id', '=', location_id]])
    execute('stock.quant', 'action_apply_inventory', quants)

print("Setup Complete.")
PYEOF

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup script finished ==="