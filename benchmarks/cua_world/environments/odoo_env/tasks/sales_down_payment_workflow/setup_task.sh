#!/bin/bash
# Setup script for sales_down_payment_workflow task
# Creates customer and product. Records initial state.

echo "=== Setting up sales_down_payment_workflow ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Function to take screenshot
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

# Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Execute Python setup script via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
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

# 1. Create Customer
customer_name = "Apex Legal Services"
existing_partner = execute('res.partner', 'search_read', [[['name', '=', customer_name]]], {'fields': ['id']})
if existing_partner:
    partner_id = existing_partner[0]['id']
    print(f"Using existing customer: {customer_name} (id={partner_id})")
else:
    partner_id = execute('res.partner', 'create', [{
        'name': customer_name,
        'is_company': True,
        'email': 'billing@apexlegal.example.com',
        'phone': '+1-202-555-0199',
    }])
    print(f"Created customer: {customer_name} (id={partner_id})")

# 2. Create Product
product_name = "Bespoke Mahogany Desk"
product_price = 4200.00
existing_product = execute('product.template', 'search_read', [[['name', '=', product_name]]], {'fields': ['id']})
if existing_product:
    product_tmpl_id = existing_product[0]['id']
    print(f"Using existing product: {product_name} (id={product_tmpl_id})")
    # Ensure price is correct
    execute('product.template', 'write', [[product_tmpl_id], {'list_price': product_price}])
else:
    product_tmpl_id = execute('product.template', 'create', [{
        'name': product_name,
        'type': 'consu',  # Consumable or Storable
        'list_price': product_price,
        'sale_ok': True,
        'taxes_id': [[6, 0, []]],  # No taxes to simplify calculation check
    }])
    print(f"Created product: {product_name} (id={product_tmpl_id})")

# 3. Ensure Down Payment Product exists (Odoo usually creates this automatically, but we check)
dp_product = execute('product.product', 'search_read', 
    [[['default_code', '=', 'DOWN']]], 
    {'fields': ['id']})
if not dp_product:
    # Try searching by name if code is missing
    dp_product = execute('product.product', 'search_read',
        [[['name', 'ilike', 'Down Payment']]],
        {'fields': ['id']})
    
if dp_product:
    print(f"Down payment product exists (id={dp_product[0]['id']})")
else:
    print("Note: Down payment product not found, Odoo should create it automatically when wizard runs.")

# Save setup data
setup_data = {
    'customer_id': partner_id,
    'customer_name': customer_name,
    'product_id': product_tmpl_id,
    'product_name': product_name,
    'target_price': product_price
}

with open('/tmp/sales_down_payment_setup.json', 'w') as f:
    json.dump(setup_data, f)

PYEOF

# Record start time
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "Setup complete."