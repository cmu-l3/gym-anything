#!/bin/bash
# Setup script for structured_quotation_builder task
# Creates the customer and necessary products.

echo "=== Setting up Structured Quotation Builder Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in {1..30}; do
    if curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null; then
        break
    fi
    sleep 2
done

# Run Python setup via XML-RPC to create data
python3 << 'PYEOF'
import xmlrpc.client
import sys
import json

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"Connection failed: {e}")
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Create Customer
customer_name = "Aurora Dynamics Inc."
existing_partner = execute('res.partner', 'search_read', [[['name', '=', customer_name]]], {'fields': ['id']})
if existing_partner:
    partner_id = existing_partner[0]['id']
    print(f"Customer '{customer_name}' exists (ID: {partner_id})")
else:
    partner_id = execute('res.partner', 'create', [{
        'name': customer_name,
        'is_company': True,
        'email': 'procurement@auroradynamics.example.com',
        'phone': '(555) 987-6543'
    }])
    print(f"Created customer '{customer_name}' (ID: {partner_id})")

# 2. Create Products
products_data = [
    {'name': 'Ergonomic Standing Desk - Bamboo Top', 'price': 749.00},
    {'name': 'Premium Mesh Task Chair', 'price': 489.00},
    {'name': '15-inch Business Laptop i7', 'price': 1299.00},
    {'name': 'Wireless Ergonomic Mouse', 'price': 59.00}
]

created_products = {}

for p in products_data:
    existing = execute('product.template', 'search_read', [[['name', '=', p['name']]]], {'fields': ['id']})
    if existing:
        pid = existing[0]['id']
        # Update price to ensure consistency
        execute('product.template', 'write', [[pid], {'list_price': p['price']}])
        print(f"Updated product '{p['name']}' (ID: {pid})")
        created_products[p['name']] = pid
    else:
        pid = execute('product.template', 'create', [{
            'name': p['name'],
            'list_price': p['price'],
            'type': 'consu',  # Consumable (simplifies stock logic)
            'sale_ok': True
        }])
        print(f"Created product '{p['name']}' (ID: {pid})")
        created_products[p['name']] = pid

# Save setup info for verifier/export
setup_info = {
    'customer_id': partner_id,
    'customer_name': customer_name,
    'products': created_products
}

with open('/tmp/structured_quotation_setup.json', 'w') as f:
    json.dump(setup_info, f)

print("Setup data saved to /tmp/structured_quotation_setup.json")
PYEOF

# Ensure Firefox is open and focused
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="