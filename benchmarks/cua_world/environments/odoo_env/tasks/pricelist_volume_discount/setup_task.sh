#!/bin/bash
# Setup script for pricelist_volume_discount task
# Creates 3 products and 1 customer for the agent to configure.

echo "=== Setting up pricelist_volume_discount ==="

# Source shared utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper to take screenshot
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

# Timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Create Products and Customer using Python/XML-RPC
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

# 1. Create Products
products_data = [
    {
        'name': 'Industrial Shelving Unit', 
        'list_price': 350.00, 
        'type': 'product', # Storable
        'detailed_type': 'product'
    },
    {
        'name': 'Ergonomic Office Chair', 
        'list_price': 250.00, 
        'type': 'product',
        'detailed_type': 'product'
    },
    {
        'name': 'Corrugated Shipping Box - Large', 
        'list_price': 12.00, 
        'type': 'consu', # Consumable
        'detailed_type': 'consu'
    }
]

created_products = {}

for p_data in products_data:
    # Check if exists
    existing = execute('product.template', 'search_read', 
        [[['name', '=', p_data['name']]]], 
        {'fields': ['id', 'name']})
    
    if existing:
        pid = existing[0]['id']
        print(f"Product '{p_data['name']}' already exists (ID: {pid})")
    else:
        pid = execute('product.template', 'create', [p_data])
        print(f"Created Product '{p_data['name']}' (ID: {pid})")
    
    created_products[p_data['name']] = pid

# 2. Create Customer
customer_name = "Cascade Distribution Partners"
existing_partner = execute('res.partner', 'search_read',
    [[['name', '=', customer_name]]],
    {'fields': ['id', 'name']})

if existing_partner:
    cid = existing_partner[0]['id']
    print(f"Customer '{customer_name}' already exists (ID: {cid})")
else:
    cid = execute('res.partner', 'create', [{
        'name': customer_name,
        'is_company': True,
        'email': 'orders@cascade-dist.example.com',
        'customer_rank': 1
    }])
    print(f"Created Customer '{customer_name}' (ID: {cid})")

# 3. Save setup metadata
setup_info = {
    'products': created_products,
    'customer_id': cid,
    'customer_name': customer_name
}

with open('/tmp/pricelist_setup.json', 'w') as f:
    json.dump(setup_info, f, indent=2)

PYEOF

# Record initial number of pricelists for verification
INITIAL_PRICELIST_COUNT=$(docker exec odoo-postgres psql -U odoo odoo_demo -t -A -c "SELECT COUNT(*) FROM product_pricelist" 2>/dev/null || echo "0")
echo "$INITIAL_PRICELIST_COUNT" > /tmp/initial_pricelist_count.txt

# Ensure Firefox is open and focused
if ! pgrep -f "firefox" > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="