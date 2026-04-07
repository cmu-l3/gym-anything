#!/bin/bash
# Setup script for product_packaging_hierarchy_sales
# Creates the product and customer, but ensures packagings are NOT defined.

echo "=== Setting up Product Packaging Hierarchy Sales task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    if curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null; then
        echo "Odoo is ready."
        break
    fi
    sleep 3
done
sleep 2

# Run Python setup via XML-RPC
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

# 1. Create Customer "GreenLife Retailers"
existing_partner = execute('res.partner', 'search_read', [[['name', '=', 'GreenLife Retailers']]], {'fields': ['id']})
if not existing_partner:
    partner_id = execute('res.partner', 'create', [{
        'name': 'GreenLife Retailers',
        'is_company': True,
        'email': 'logistics@greenlife.example.com',
        'street': '123 Eco Way',
        'city': 'Portland',
        'state_id': 44, # Oregon
        'zip': '97204'
    }])
    print(f"Created customer: GreenLife Retailers (id={partner_id})")
else:
    print("Customer GreenLife Retailers already exists")

# 2. Create Product "Bamboo Fiber Bento Box"
existing_product = execute('product.template', 'search_read', [[['name', '=', 'Bamboo Fiber Bento Box']]], {'fields': ['id']})
if not existing_product:
    product_tmpl_id = execute('product.template', 'create', [{
        'name': 'Bamboo Fiber Bento Box',
        'type': 'product', # Storable
        'list_price': 18.50,
        'standard_price': 9.20,
        'default_code': 'BENTO-001'
    }])
    print(f"Created product: Bamboo Fiber Bento Box (id={product_tmpl_id})")
else:
    product_tmpl_id = existing_product[0]['id']
    # Ensure no packagings exist for this product
    packagings = execute('product.packaging', 'search', [[['product_id.product_tmpl_id', '=', product_tmpl_id]]])
    if packagings:
        execute('product.packaging', 'unlink', [packagings])
        print("Removed existing packagings for product")

# 3. Attempt to disable 'Product Packagings' setting (stock.group_stock_packaging)
# This forces the user to enable it. We do this by removing the group from the admin user.
try:
    # Find the group
    group_ids = execute('res.groups', 'search', [[['name', 'ilike', 'packaging']]])
    if group_ids:
        # Check if admin has it
        user = execute('res.users', 'read', [uid], {'fields': ['groups_id']})[0]
        current_groups = user['groups_id']
        
        # Identify which groups to remove (intersection)
        to_remove = [g for g in group_ids if g in current_groups]
        
        if to_remove:
            # Remove the group from the user
            execute('res.users', 'write', [[uid], {'groups_id': [(3, g_id) for g_id in to_remove]}])
            print(f"Disabled packaging groups for admin user to reset state.")
except Exception as e:
    print(f"Warning: Could not disable packaging setting: {e}")

print("Setup complete.")
PYEOF

# Ensure Firefox is running
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    /workspace/scripts/setup_odoo.sh
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Navigate to home
if [ -x "$(command -v safe_xdotool)" ]; then
    safe_xdotool ga :1 key ctrl+l
    safe_xdotool ga :1 type "http://localhost:8069/web"
    safe_xdotool ga :1 key Return
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="