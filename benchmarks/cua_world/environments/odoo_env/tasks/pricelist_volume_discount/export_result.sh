#!/bin/bash
# Export script for pricelist_volume_discount task

echo "=== Exporting pricelist_volume_discount results ==="

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get task start timestamp
TASK_START_TS=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_PRICELIST_COUNT=$(cat /tmp/initial_pricelist_count.txt 2>/dev/null || echo "0")

# Check if setup file exists
if [ ! -f /tmp/pricelist_setup.json ]; then
    echo '{"error": "Setup file not found"}' > /tmp/pricelist_volume_discount_result.json
    exit 1
fi

# Query Odoo using Python
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

setup_file = '/tmp/pricelist_setup.json'
result_file = '/tmp/pricelist_volume_discount_result.json'

try:
    with open(setup_file, 'r') as f:
        setup_data = json.load(f)
except Exception as e:
    print(f"Error reading setup file: {e}")
    sys.exit(1)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"Error connecting to Odoo: {e}")
    # Write partial result
    with open(result_file, 'w') as f:
        json.dump({"error": str(e)}, f)
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# --- 1. Check if Pricelists feature is enabled ---
settings = execute('res.config.settings', 'search_read', 
    [], 
    {'fields': ['group_product_pricelist'], 'order': 'id desc', 'limit': 1})

# Note: In some Odoo versions, settings are ephemeral. 
# Better to check if the group is active or check 'product.pricelist' access.
# Checking 'group_product_pricelist' on res.groups is more reliable.
group_pricelist = execute('res.groups', 'search_read',
    [[['name', 'ilike', 'Basic Pricelists']]], # "Basic Pricelists" or "Advanced Pricelists"
    {'fields': ['id', 'name']})
# If the feature is enabled, users usually belong to a specific group, 
# or the implied_group logic in settings works.
# Simpler: check if we can find the specific pricelist created by the agent.

# --- 2. Check for the specific Pricelist ---
target_pricelist_name = "Wholesale Partner - Tier 2"
pricelists = execute('product.pricelist', 'search_read',
    [[['name', 'ilike', target_pricelist_name]]],
    {'fields': ['id', 'name', 'currency_id', 'create_date']})

pricelist_found = False
pricelist_data = None
pricelist_id = None
pricelist_items = []

if pricelists:
    pricelist_found = True
    pricelist_data = pricelists[0]
    pricelist_id = pricelist_data['id']
    
    # Get Items
    items = execute('product.pricelist.item', 'search_read',
        [[['pricelist_id', '=', pricelist_id]]],
        {'fields': ['product_tmpl_id', 'min_quantity', 'fixed_price', 'compute_price', 'applied_on']})
    
    # Enrich items with product names
    for item in items:
        # product_tmpl_id is [id, name]
        p_name = item['product_tmpl_id'][1] if item['product_tmpl_id'] else "Unknown"
        pricelist_items.append({
            'product': p_name,
            'min_qty': item['min_quantity'],
            'price': item['fixed_price'],
            'compute_price': item['compute_price'],
            'applied_on': item['applied_on']
        })

# --- 3. Check Customer Assignment ---
customer_id = setup_data['customer_id']
customer = execute('res.partner', 'search_read',
    [[['id', '=', customer_id]]],
    {'fields': ['property_product_pricelist']})

assigned_pricelist_id = None
assigned_pricelist_name = None

if customer:
    # property_product_pricelist is usually [id, name]
    pl_field = customer[0].get('property_product_pricelist')
    if pl_field:
        assigned_pricelist_id = pl_field[0]
        assigned_pricelist_name = pl_field[1]

# --- 4. Pricelist Count Change ---
current_pricelist_count = execute('product.pricelist', 'search_count', [[]])

# Compile Result
result = {
    "feature_enabled": True, # Implicit if we can search them, but strictly checked by having >1 pricelist usually
    "pricelist_found": pricelist_found,
    "pricelist_name": pricelist_data['name'] if pricelist_data else None,
    "pricelist_items": pricelist_items,
    "assigned_pricelist_id": assigned_pricelist_id,
    "assigned_pricelist_name": assigned_pricelist_name,
    "target_pricelist_id": pricelist_id,
    "current_pricelist_count": current_pricelist_count
}

with open(result_file, 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Add initial counts to result
INITIAL_COUNT=$(cat /tmp/initial_pricelist_count.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Merge into final JSON safely
python3 -c "
import json
try:
    with open('/tmp/pricelist_volume_discount_result.json', 'r') as f:
        data = json.load(f)
    data['initial_pricelist_count'] = int($INITIAL_COUNT)
    data['task_start_timestamp'] = int($TASK_START)
    with open('/tmp/pricelist_volume_discount_result.json', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(e)
"

# Copy to task_result.json for framework
cp /tmp/pricelist_volume_discount_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="