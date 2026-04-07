#!/bin/bash
# Setup script for ecommerce_catalog_optimization
# Installs website_sale module and creates required products without relations.

echo "=== Setting up eCommerce Catalog Optimization Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 60); do
    if curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null; then
        echo "Odoo XML-RPC ready."
        break
    fi
    sleep 2
done

# Run Python setup
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import time

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

def get_connection():
    try:
        common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
        uid = common.authenticate(DB, USERNAME, PASSWORD, {})
        models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
        return uid, models
    except Exception as e:
        print(f"Connection error: {e}", file=sys.stderr)
        return None, None

uid, models = get_connection()
if not uid:
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Install Website Sale module if not installed
print("Checking website_sale module...")
module = execute('ir.module.module', 'search_read', 
    [[['name', '=', 'website_sale']]], {'fields': ['state', 'id']})

if module and module[0]['state'] != 'installed':
    print("Installing website_sale (this may take a minute)...")
    execute('ir.module.module', 'button_immediate_install', [[module[0]['id']]])
    # Re-authenticate after module install (registry reload)
    time.sleep(10)
    uid, models = get_connection()

# 2. Create Products
products_to_create = [
    {
        'name': 'Motorized Bamboo Desk',
        'list_price': 850.00,
        'type': 'product',
        'is_published': True, 
        'description_sale': 'Premium motorized desk.'
    },
    {
        'name': 'Cable Management Box',
        'list_price': 25.00,
        'type': 'consu',
        'is_published': True,
        'description_sale': 'Hide your cables.'
    },
    {
        'name': 'Bamboo Standing Desk',
        'list_price': 450.00,
        'type': 'product',
        'is_published': False, # Start unpublished
        'description_sale': 'Eco-friendly standing desk.'
    },
    {
        'name': 'Recycled Paper Organizer',
        'list_price': 15.00,
        'type': 'consu',
        'is_published': False, # Start unpublished
        'description_sale': 'Organize with recycled materials.'
    }
]

created_ids = {}

for p in products_to_create:
    # Check if exists
    existing = execute('product.template', 'search_read', 
        [[['name', '=', p['name']]]], {'fields': ['id']})
    
    if existing:
        pid = existing[0]['id']
        # Reset state to ensure clean start
        execute('product.template', 'write', [[pid], {
            'is_published': p['is_published'],
            'public_categ_ids': [[5]], # Remove all categories (command 5)
            'alternative_product_ids': [[5]],
            'accessory_product_ids': [[5]]
        }])
        print(f"Reset existing product: {p['name']} (ID: {pid})")
        created_ids[p['name']] = pid
    else:
        pid = execute('product.template', 'create', [p])
        print(f"Created product: {p['name']} (ID: {pid})")
        created_ids[p['name']] = pid

# 3. Create Ribbon (if needed, usually exists in data, but ensure 'New!')
ribbon = execute('product.ribbon', 'search', [[['html', 'ilike', 'New']]])
if not ribbon:
    execute('product.ribbon', 'create', [{'html': 'New!', 'bg_color': '#28a745', 'text_color': '#ffffff'}])

# 4. Save setup data
setup_data = {
    'main_product_id': created_ids['Bamboo Standing Desk'],
    'upsell_product_id': created_ids['Motorized Bamboo Desk'],
    'cross_sell_product_id': created_ids['Cable Management Box'],
    'draft_product_id': created_ids['Recycled Paper Organizer'],
    'start_time': time.time()
}

with open('/tmp/ecommerce_setup.json', 'w') as f:
    json.dump(setup_data, f)

print("Setup complete.")
PYEOF

# Ensure Firefox is open and focused on Odoo
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="