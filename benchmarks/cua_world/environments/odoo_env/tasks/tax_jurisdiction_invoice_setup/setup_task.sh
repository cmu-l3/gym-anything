#!/bin/bash
# Setup script for tax_jurisdiction_invoice_setup task
# Creates the necessary Customer and Products.
# Records start time for anti-gaming verification.

echo "=== Setting up tax_jurisdiction_invoice_setup ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Execute Python setup script via XML-RPC
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

# 1. Create Customer
CUSTOMER_NAME = "Riverside Office Solutions"
existing_partner = execute('res.partner', 'search_read', [[['name', '=', CUSTOMER_NAME]]], {'fields': ['id']})
if existing_partner:
    partner_id = existing_partner[0]['id']
    print(f"Using existing partner: {CUSTOMER_NAME} (ID: {partner_id})")
else:
    partner_id = execute('res.partner', 'create', [{
        'name': CUSTOMER_NAME,
        'is_company': True,
        'email': 'accounts@riverside.example.com',
        'city': 'Albany',
        'state_id': 36, # NY usually, but using ID might be risky if demo data varies. Leaving blank/default fine.
        'zip': '12207'
    }])
    print(f"Created partner: {CUSTOMER_NAME} (ID: {partner_id})")

# 2. Create Products
products_data = [
    {
        'name': 'Office Standing Desk',
        'list_price': 749.00,
        'default_code': 'DESK-STAND-001',
        'type': 'consu'
    },
    {
        'name': 'Ergonomic Task Chair',
        'list_price': 389.00,
        'default_code': 'CHAIR-ERGO-002',
        'type': 'consu'
    }
]

created_product_ids = {}

for p_data in products_data:
    existing_prod = execute('product.template', 'search_read', [[['name', '=', p_data['name']]]], {'fields': ['id']})
    if existing_prod:
        p_id = existing_prod[0]['id']
        # Reset taxes to ensure clean state (remove default taxes)
        execute('product.template', 'write', [[p_id], {'taxes_id': [[6, 0, []]]}]) 
        print(f"Using existing product: {p_data['name']} (ID: {p_id}) - Cleared taxes")
    else:
        p_id = execute('product.template', 'create', [{
            'name': p_data['name'],
            'list_price': p_data['list_price'],
            'default_code': p_data['default_code'],
            'type': p_data['type'],
            'taxes_id': [[6, 0, []]] # Create with NO taxes initially
        }])
        print(f"Created product: {p_data['name']} (ID: {p_id})")
    created_product_ids[p_data['name']] = p_id

# Save setup metadata for export/verification
setup_data = {
    'partner_id': partner_id,
    'partner_name': CUSTOMER_NAME,
    'products': created_product_ids
}

with open('/tmp/tax_setup_metadata.json', 'w') as f:
    json.dump(setup_data, f)

print("Setup complete.")
PYEOF

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="