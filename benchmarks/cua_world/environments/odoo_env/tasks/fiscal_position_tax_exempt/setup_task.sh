#!/bin/bash
# Setup script for fiscal_position_tax_exempt task
# Creates necessary products with default taxes applied.
# The agent must create the fiscal position and customer themselves.

echo "=== Setting up fiscal_position_tax_exempt ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Use Python to set up data via XML-RPC
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

# 1. Find the default sales tax (usually 15% in demo data, or any sales tax)
# We look for a tax that is active, type 'sale', and amount > 0
taxes = execute('account.tax', 'search_read',
    [[['type_tax_use', '=', 'sale'], ['amount', '>', 0], ['active', '=', True]]],
    {'fields': ['id', 'name', 'amount'], 'limit': 1})

if not taxes:
    # If no tax found, create one (unlikely in demo data but good fallback)
    tax_id = execute('account.tax', 'create', [{
        'name': 'Sales Tax 15%',
        'type_tax_use': 'sale',
        'amount': 15.0,
        'amount_type': 'percent'
    }])
    tax_name = 'Sales Tax 15%'
    print(f"Created sales tax: {tax_name} (id={tax_id})")
else:
    tax_id = taxes[0]['id']
    tax_name = taxes[0]['name']
    print(f"Using existing sales tax: {tax_name} (id={tax_id})")

# 2. Create Products with this tax
products_data = [
    {
        'name': 'Organic Compost Bin - Large',
        'list_price': 89.00,
        'taxes_id': [[6, 0, [tax_id]]]
    },
    {
        'name': 'Solar-Powered Garden Light Set',
        'list_price': 145.00,
        'taxes_id': [[6, 0, [tax_id]]]
    }
]

created_products = []
for p_data in products_data:
    # Check if exists first
    existing = execute('product.template', 'search_read',
        [[['name', '=', p_data['name']]]],
        {'fields': ['id', 'name']})
    
    if existing:
        pid = existing[0]['id']
        # Ensure tax is set
        execute('product.template', 'write', [[pid], {'taxes_id': [[6, 0, [tax_id]]]}])
        print(f"Updated existing product: {p_data['name']}")
    else:
        pid = execute('product.template', 'create', [p_data])
        print(f"Created product: {p_data['name']}")
    
    created_products.append({'id': pid, 'name': p_data['name'], 'price': p_data['list_price']})

# 3. Save setup data for verification
setup_info = {
    'default_tax_id': tax_id,
    'default_tax_name': tax_name,
    'products': created_products
}

with open('/tmp/fiscal_position_setup.json', 'w') as f:
    json.dump(setup_info, f, indent=2)

print("Setup data saved to /tmp/fiscal_position_setup.json")
PYEOF

# Ensure Firefox is started and maximized (standard env setup usually handles this, 
# but we enforce it for the specific task flow)
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="