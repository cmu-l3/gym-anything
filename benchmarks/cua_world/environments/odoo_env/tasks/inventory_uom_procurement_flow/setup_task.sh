#!/bin/bash
# Setup script for inventory_uom_procurement_flow
# 1. Creates vendor "AquaPure Supplies"
# 2. Ensures "Units of Measure" setting is DISABLED (agent must enable it)
# 3. Ensures the target product does not exist

echo "=== Setting up inventory_uom_procurement_flow ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Execute setup via Python/XMLRPC
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

# 1. Create Vendor
vendor_name = "AquaPure Supplies"
existing_vendor = execute('res.partner', 'search_read', 
    [[['name', '=', vendor_name]]], 
    {'fields': ['id']})

if not existing_vendor:
    vendor_id = execute('res.partner', 'create', [{
        'name': vendor_name,
        'is_company': True,
        'supplier_rank': 1
    }])
    print(f"Created vendor: {vendor_name} (ID: {vendor_id})")
else:
    print(f"Vendor exists: {vendor_name}")

# 2. Ensure UoM feature is DISABLED initially
# In Odoo, this is often controlled by the 'uom.group_uom' group.
# We remove the admin user from this group to force the "Enable UoM" step.
# Note: Changing settings in res.config.settings usually toggles this group.

# Find the group
uom_group = execute('res.groups', 'search_read', 
    [[['name', '=', 'Units of Measure'], ['category_id.name', 'ilike', 'Inventory']]], 
    {'fields': ['id']})

if uom_group:
    gid = uom_group[0]['id']
    # Remove admin (uid) from this group
    execute('res.groups', 'write', [[gid], {'users': [(3, uid)]}]) 
    print("Disabled 'Units of Measure' feature for admin user.")

# 3. Cleanup: Remove product if it exists from previous run
product_name = "Glacier Spring Water 500ml"
existing_products = execute('product.template', 'search', [[['name', '=', product_name]]])
if existing_products:
    print(f"Removing existing product '{product_name}'...")
    execute('product.template', 'unlink', [existing_products])

# 4. Remove 'Case of 24' UoM if it exists
uom_name = "Case of 24"
existing_uoms = execute('uom.uom', 'search', [[['name', '=', uom_name]]])
if existing_uoms:
    print(f"Removing existing UoM '{uom_name}'...")
    execute('uom.uom', 'unlink', [existing_uoms])

print("Setup complete.")
PYEOF

# Ensure Odoo web interface is ready
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' > /dev/null 2>&1 &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Task Complete ==="