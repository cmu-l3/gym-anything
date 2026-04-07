#!/bin/bash
# Setup script for loyalty_promotion_setup task
# Creates the specific product and customer needed for the task.
# Ensures the environment is clean of previous attempts at this specific promotion.

echo "=== Setting up loyalty_promotion_setup ==="

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
sleep 2

# Run Python setup via XML-RPC
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

# 1. Create or Find Product: Lumina Privacy Screen
PRODUCT_NAME = "Lumina Privacy Screen"
product_id = 0

existing_prod = execute('product.template', 'search_read',
    [[['name', '=', PRODUCT_NAME]]],
    {'fields': ['id', 'name'], 'limit': 1})

if existing_prod:
    product_id = existing_prod[0]['id']
    print(f"Using existing product: {PRODUCT_NAME} (id={product_id})")
else:
    product_id = execute('product.template', 'create', [{
        'name': PRODUCT_NAME,
        'list_price': 120.00,
        'type': 'consu', # Consumable to avoid stock warnings for this task
        'sale_ok': True,
    }])
    print(f"Created product: {PRODUCT_NAME} (id={product_id})")

# 2. Create or Find Customer: Apex Interiors
CUSTOMER_NAME = "Apex Interiors"
partner_id = 0

existing_partner = execute('res.partner', 'search_read',
    [[['name', '=', CUSTOMER_NAME]]],
    {'fields': ['id', 'name'], 'limit': 1})

if existing_partner:
    partner_id = existing_partner[0]['id']
    print(f"Using existing customer: {CUSTOMER_NAME} (id={partner_id})")
else:
    partner_id = execute('res.partner', 'create', [{
        'name': CUSTOMER_NAME,
        'is_company': True,
        'email': 'procurement@apexinteriors.example.com',
    }])
    print(f"Created customer: {CUSTOMER_NAME} (id={partner_id})")

# 3. Clean up existing promotions with the target code/name to prevent collisions
PROGRAM_NAME = "Privacy Screen Bulk Saver"
PROMO_CODE = "SCREEN15"

# Find programs to delete
programs_to_delete = execute('loyalty.program', 'search',
    ['|', ['name', '=', PROGRAM_NAME], ['trigger', '=', 'code']])
# Note: 'trigger' field value for code might depend on version, checking name is safer
# Deleting might be restricted, so we might just rename/archive them if delete fails
# But for a task environment, deletion is usually fine.

if programs_to_delete:
    print(f"Cleaning up {len(programs_to_delete)} conflicting programs...")
    try:
        execute('loyalty.program', 'unlink', [programs_to_delete])
    except Exception as e:
        print(f"Warning: Could not delete existing programs: {e}")
        # Archive them instead
        execute('loyalty.program', 'write', [programs_to_delete, {'active': False}])

# 4. Save setup data
setup_data = {
    'product_id': product_id,
    'product_name': PRODUCT_NAME,
    'partner_id': partner_id,
    'partner_name': CUSTOMER_NAME,
    'target_program_name': PROGRAM_NAME,
    'target_code': PROMO_CODE
}

with open('/tmp/loyalty_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print("Setup complete.")
PYEOF

# Ensure Firefox is open (common Odoo task requirement)
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="