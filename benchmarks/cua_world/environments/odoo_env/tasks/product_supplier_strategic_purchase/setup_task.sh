#!/bin/bash
# Setup script for product_supplier_strategic_purchase task
# Creates the product and vendors, and writes the requirements file to Desktop.

echo "=== Setting up product_supplier_strategic_purchase ==="

# Source shared utilities
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

# Python script to setup Odoo data
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

# 1. Create Vendors
vendors = [
    {'name': 'Allied Industrial Supply Co.', 'is_company': True, 'supplier_rank': 1},
    {'name': 'Pacific Bearing Solutions', 'is_company': True, 'supplier_rank': 1}
]

vendor_ids = {}
for v_data in vendors:
    # Check if exists
    existing = execute('res.partner', 'search_read', [[['name', '=', v_data['name']]]], {'fields': ['id']})
    if existing:
        vendor_ids[v_data['name']] = existing[0]['id']
        print(f"Using existing vendor: {v_data['name']}")
    else:
        new_id = execute('res.partner', 'create', [v_data])
        vendor_ids[v_data['name']] = new_id
        print(f"Created vendor: {v_data['name']}")

# 2. Create Product (clean slate: ensure no existing supplier info if it already exists)
prod_name = "Precision Ball Bearing - 6205-2RS"
existing_prod = execute('product.template', 'search_read', [[['name', '=', prod_name]]], {'fields': ['id']})

if existing_prod:
    prod_id = existing_prod[0]['id']
    # Clear any existing supplier info
    supplier_infos = execute('product.supplierinfo', 'search', [[['product_tmpl_id', '=', prod_id]]])
    if supplier_infos:
        execute('product.supplierinfo', 'unlink', [supplier_infos])
    print(f"Using existing product (cleaned): {prod_name}")
else:
    prod_id = execute('product.template', 'create', [{
        'name': prod_name,
        'type': 'product', # Storable product
        'purchase_ok': True,
        'standard_price': 12.00,
        'list_price': 18.50,
        'categ_id': 1 # All
    }])
    print(f"Created product: {prod_name}")

# Save setup metadata
setup_data = {
    'product_id': prod_id,
    'product_name': prod_name,
    'vendors': vendor_ids
}
with open('/tmp/supplier_purchase_setup.json', 'w') as f:
    json.dump(setup_data, f)

PYEOF

# Create Requirements File on Desktop
cat > /home/ga/Desktop/purchasing_requirements.txt << 'EOF'
PURCHASING REQUIREMENTS - Precision Ball Bearing 6205-2RS
=========================================================

The engineering team requires 500 units of "Precision Ball Bearing - 6205-2RS".

Two vendors have provided quotes. Please add both suppliers' pricing
information to the product record in Odoo, then create and confirm a
purchase order from the most cost-effective supplier.

Vendor Quotes:
--------------
1. Allied Industrial Supply Co.
   - Unit Price: $12.50
   - Minimum Order Quantity: 100 units
   - Delivery Lead Time: 14 days

2. Pacific Bearing Solutions
   - Unit Price: $11.80
   - Minimum Order Quantity: 250 units
   - Delivery Lead Time: 21 days

Order Requirement: 500 units

Instructions:
- Add BOTH vendors' pricing to the product's Purchase tab
- Create and confirm a purchase order for 500 units from the 
  vendor offering the lowest unit price
EOF

# Ensure permissions
chown ga:ga /home/ga/Desktop/purchasing_requirements.txt
chmod 644 /home/ga/Desktop/purchasing_requirements.txt

# Launch Firefox to Odoo login page
echo "Ensuring Firefox is running..."
ODOO_LOGIN_URL="http://localhost:8069/web/login?db=odoo_demo"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$ODOO_LOGIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for window and maximize
if wait_for_window "firefox\|mozilla\|Odoo" 30; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="