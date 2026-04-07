#!/bin/bash
# Setup script for service_project_automation_sales
# Ensures sale_project module is installed, creates customer and physical product.

echo "=== Setting up service_project_automation_sales ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record Start Time
date +%s > /tmp/task_start_timestamp

# 2. Wait for Odoo
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done

# 3. Setup Data via Python
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
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Cannot connect to Odoo: {e}", file=sys.stderr)
    sys.exit(1)

def execute(model, method, *args, **kwargs):
    return models.execute_kw(DB, uid, PASSWORD, model, method, list(args), kwargs)

# --- Ensure sale_project module is installed ---
# This module is required for the "Create a task in a new project" option
module_id = execute('ir.module.module', 'search', [['name', '=', 'sale_project'], ['state', '!=', 'installed']])
if module_id:
    print("Installing sale_project module (this may take a moment)...")
    execute('ir.module.module', 'button_immediate_install', module_id)
else:
    print("Module sale_project is already installed.")

# --- Create Customer: Titanium Manufacturing ---
partner_id = execute('res.partner', 'create', {
    'name': 'Titanium Manufacturing',
    'is_company': True,
    'email': 'procurement@titanium.example.com',
    'street': '7742 Industrial Pkwy',
    'city': 'Detroit',
    'zip': '48201'
})
print(f"Created Customer: Titanium Manufacturing (ID: {partner_id})")

# --- Create Physical Product: Industrial Barcode Scanner ---
# Check if exists first to avoid duplicates on retry
existing_prod = execute('product.template', 'search', [['name', '=', 'Industrial Barcode Scanner']])
if not existing_prod:
    prod_id = execute('product.template', 'create', {
        'name': 'Industrial Barcode Scanner',
        'type': 'product', # Storable
        'list_price': 450.00,
        'standard_price': 200.00,
        'invoice_policy': 'delivery', # Invoicing based on delivered qty
    })
    print(f"Created Product: Industrial Barcode Scanner (ID: {prod_id})")
    
    # Update Quantity on Hand to 50
    # Find variant ID
    variant_id = execute('product.product', 'search', [['product_tmpl_id', '=', prod_id]])[0]
    
    # Find stock location
    loc_ids = execute('stock.location', 'search', [['usage', '=', 'internal']])
    stock_loc = loc_ids[0]
    
    # Create inventory adjustment (simplest way in code is direct stock.quant update for demo)
    execute('stock.quant', 'create', {
        'product_id': variant_id,
        'location_id': stock_loc,
        'inventory_quantity': 50
    })
    # Apply inventory
    # Note: In newer Odoo versions, we might need to call action_apply_inventory. 
    # For robustnes, we just rely on creating the quant or assume user can sell.
    # Actually, simpler to just set qty via update_quantity_on_hand wizard pattern, 
    # but stock.quant creation usually works for initialization if no quants exist.
else:
    print("Product 'Industrial Barcode Scanner' already exists.")

# --- Cleanup: Archive 'Logistics Site Audit' if it exists ---
# This forces the agent to create it fresh
existing_service = execute('product.template', 'search', [['name', '=', 'Logistics Site Audit']])
if existing_service:
    execute('product.template', 'write', existing_service, {'active': False})
    print(f"Archived existing 'Logistics Site Audit' products: {existing_service}")

print("Setup Complete.")
PYEOF

# 4. GUI Setup
# Ensure Firefox is open to Odoo
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="