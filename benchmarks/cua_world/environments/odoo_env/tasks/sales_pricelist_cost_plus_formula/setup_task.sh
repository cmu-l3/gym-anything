#!/bin/bash
# Setup script for sales_pricelist_cost_plus_formula
# 1. Ensures Pricelists feature is enabled
# 2. Sets up product "Office Lamp" with fixed cost $20.00
# 3. Ensures customer "Azure Interior" exists

echo "=== Setting up sales_pricelist_cost_plus_formula ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

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

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Enable Pricelists (group_product_pricelist)
# We do this by updating res.config.settings
# Note: In some Odoo versions this is 'group_product_pricelist', in others 'group_sale_pricelist'
# We'll try to enable the group directly on the user to be safe
try:
    # Find the group
    groups = execute('res.groups', 'search_read', 
        [[['name', 'ilike', 'Pricelists']]], 
        {'fields': ['id', 'name']})
    
    if groups:
        group_id = groups[0]['id']
        # Add admin user to this group
        execute('res.users', 'write', [[uid], {'groups_id': [(4, group_id)]}])
        print(f"Enabled pricelist group {group_id} for user")
    
    # Also try settings
    settings_id = execute('res.config.settings', 'create', [{'group_product_pricelist': True}])
    execute('res.config.settings', 'execute', [[settings_id]])
    print("Applied pricelist settings")
except Exception as e:
    print(f"Warning setting up pricelists: {e}")

# 2. Setup Product "Office Lamp" with Cost $20.00
PRODUCT_NAME = "Office Lamp"
COST = 20.00

# Find or create product
existing = execute('product.product', 'search_read', 
    [[['name', '=', PRODUCT_NAME]]], 
    {'fields': ['id', 'name'], 'limit': 1})

if existing:
    prod_id = existing[0]['id']
    execute('product.product', 'write', [[prod_id], {'standard_price': COST}])
    print(f"Updated product '{PRODUCT_NAME}' (id={prod_id}) cost to ${COST}")
else:
    prod_id = execute('product.product', 'create', [{
        'name': PRODUCT_NAME,
        'standard_price': COST,
        'list_price': 1.0, # Arbitrary, formula should override
        'type': 'product'
    }])
    print(f"Created product '{PRODUCT_NAME}' (id={prod_id}) with cost ${COST}")

# 3. Ensure Customer "Azure Interior"
CUSTOMER_NAME = "Azure Interior"
existing_partner = execute('res.partner', 'search_read', 
    [[['name', '=', CUSTOMER_NAME]]], 
    {'fields': ['id'], 'limit': 1})

if existing_partner:
    partner_id = existing_partner[0]['id']
else:
    partner_id = execute('res.partner', 'create', [{'name': CUSTOMER_NAME}])
    print(f"Created customer '{CUSTOMER_NAME}'")

# Save metadata
import json
with open('/tmp/pricelist_setup.json', 'w') as f:
    json.dump({
        'product_id': prod_id,
        'product_name': PRODUCT_NAME,
        'cost': COST,
        'partner_id': partner_id,
        'partner_name': CUSTOMER_NAME
    }, f)

PYEOF

# Ensure Firefox is open and ready
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="