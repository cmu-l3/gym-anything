#!/bin/bash
# Setup script for manufacturing_variant_bom_setup task
# Creates the "Ergo-Flex Desk" product template with variants and all required component products.

echo "=== Setting up manufacturing_variant_bom_setup ==="

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

# Install Manufacturing if needed (usually installed, but ensure)
# We assume it's there based on env, but we'll check via python if we can access mrp models

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

# 1. Ensure MRP is installed
try:
    execute('mrp.bom', 'search', [[]], {'limit': 1})
except Exception:
    print("Installing Manufacturing app...")
    # This is heavy, usually pre-installed in env, but here we just fail if missing
    print("ERROR: Manufacturing (mrp) module not accessible.", file=sys.stderr)
    sys.exit(1)

# 2. Create Attributes
def get_or_create_attribute(name, values):
    existing = execute('product.attribute', 'search_read', [[['name', '=', name]]], {'fields': ['id']})
    if existing:
        attr_id = existing[0]['id']
    else:
        attr_id = execute('product.attribute', 'create', [{'name': name, 'create_variant': 'always'}])
    
    value_ids = {}
    for val in values:
        existing_val = execute('product.attribute.value', 'search_read', 
            [[['attribute_id', '=', attr_id], ['name', '=', val]]], {'fields': ['id']})
        if existing_val:
            value_ids[val] = existing_val[0]['id']
        else:
            value_ids[val] = execute('product.attribute.value', 'create', 
                [{'attribute_id': attr_id, 'name': val}])
    return attr_id, value_ids

attr_edition_id, edition_vals = get_or_create_attribute("Edition", ["Standard", "Pro"])
attr_finish_id, finish_vals = get_or_create_attribute("Finish", ["Oak", "White"])

print(f"Attributes ready: Edition={attr_edition_id}, Finish={attr_finish_id}")

# 3. Create Product Template "Ergo-Flex Desk"
template_name = "Ergo-Flex Desk"
existing_tmpl = execute('product.template', 'search_read', [[['name', '=', template_name]]], {'fields': ['id']})

if existing_tmpl:
    # Cleanup old one to ensure clean state
    execute('product.template', 'unlink', [[existing_tmpl[0]['id']]])

# Create new template
tmpl_id = execute('product.template', 'create', [{
    'name': template_name,
    'type': 'product', # Storable
    'detailed_type': 'product',
}])

# Add attributes to template (this generates variants and PTAVs)
# Note: In Odoo, we write to attribute_line_ids
execute('product.template', 'write', [[tmpl_id], {
    'attribute_line_ids': [
        (0, 0, {
            'attribute_id': attr_edition_id,
            'value_ids': [(6, 0, list(edition_vals.values()))]
        }),
        (0, 0, {
            'attribute_id': attr_finish_id,
            'value_ids': [(6, 0, list(finish_vals.values()))]
        })
    ]
}])

print(f"Created Product Template: {template_name} (id={tmpl_id})")

# 4. Get Product Template Attribute Values (PTAVs)
# These are the specific IDs needed for the BoM configuration
ptavs = {}
# Query product.template.attribute.value
# We need to map "Standard" -> ptav_id, "Pro" -> ptav_id, etc.
lines = execute('product.template.attribute.line', 'search_read', 
    [[['product_tmpl_id', '=', tmpl_id]]], {'fields': ['attribute_id', 'product_template_value_ids']})

for line in lines:
    # fetch the values details
    ptav_records = execute('product.template.attribute.value', 'read', 
        line['product_template_value_ids'], ['name', 'product_attribute_value_id'])
    for ptav in ptav_records:
        ptavs[ptav['name']] = ptav['id']

print("PTAV Mapping:", ptavs)

# 5. Create Components
components_data = {
    "Desk Frame (Universal)": 150.0,
    "Standard Motor Unit": 80.0,
    "Pro Heavy-Duty Motor Unit": 120.0,
    "Oak Desktop Board": 60.0,
    "White Desktop Board": 55.0,
    "Cable Management Tray": 25.0,
    "Assembly Hardware Kit": 15.0
}

component_ids = {}

for name, cost in components_data.items():
    # Check existence
    existing = execute('product.product', 'search_read', [[['name', '=', name]]], {'fields': ['id']})
    if existing:
        comp_id = existing[0]['id']
    else:
        comp_id = execute('product.product', 'create', [{
            'name': name,
            'type': 'product',
            'detailed_type': 'product',
            'standard_price': cost,
            'list_price': cost * 1.5
        }])
    component_ids[name] = comp_id
    
    # Update inventory so they are available (optional but good for testing)
    # Finding stock location
    locs = execute('stock.location', 'search', [[['usage', '=', 'internal']]], {'limit': 1})
    if locs:
        execute('stock.quant', 'create', [{
            'product_id': comp_id,
            'location_id': locs[0],
            'inventory_quantity': 100
        }])
        # Apply inventory... Odoo 16+ requires action_apply, simplified here
        # We'll skip complex inventory application as BoM setup doesn't strictly require stock to exist, just records.

print("Components created:", component_ids)

# 6. Save Setup Data for export script
setup_data = {
    "template_id": tmpl_id,
    "ptavs": ptavs, # Name -> ID
    "components": component_ids # Name -> ID
}

with open('/tmp/bom_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print("Setup complete.")
PYEOF

# Ensure Manufacturing app is visible
echo "Ensuring user is on Manufacturing dashboard..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web#action=mrp.mrp_production_action' &"

# Wait and maximize
sleep 5
DISPLAY=:1 wmctrl -r "Odoo" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="