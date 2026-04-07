#!/bin/bash
# Setup script for payment_terms_installment_invoice
# Creates the customer and products required for the task.

echo "=== Setting up Payment Terms Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in {1..30}; do
    if curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null; then
        echo "Odoo is ready."
        break
    fi
    sleep 3
done

# 3. Create Data via Python/XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import sys
import json

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"Connection failed: {e}")
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Create Customer
partner_name = "Pinnacle Industries"
existing_partner = execute('res.partner', 'search_read', [[['name', '=', partner_name]]], {'fields': ['id']})
if existing_partner:
    partner_id = existing_partner[0]['id']
    print(f"Partner exists: {partner_id}")
else:
    partner_id = execute('res.partner', 'create', [{
        'name': partner_name,
        'is_company': True,
        'email': 'accounting@pinnacle.example.com',
        'property_payment_term_id': False  # Ensure no default term implies the answer
    }])
    print(f"Created Partner: {partner_id}")

# Create Products
products = [
    {'name': 'Industrial Control Panel', 'price': 750.0},
    {'name': 'Sensor Array Module', 'price': 500.0}
]

product_ids = {}
for p in products:
    existing = execute('product.template', 'search_read', [[['name', '=', p['name']]]], {'fields': ['id']})
    if existing:
        pid = existing[0]['id']
    else:
        pid = execute('product.template', 'create', [{
            'name': p['name'],
            'list_price': p['price'],
            'type': 'consu',
            'sale_ok': True
        }])
    product_ids[p['name']] = pid
    print(f"Product {p['name']}: {pid}")

# Save setup data
setup_data = {
    'partner_id': partner_id,
    'partner_name': partner_name,
    'product_ids': product_ids
}

with open('/tmp/payment_terms_setup.json', 'w') as f:
    json.dump(setup_data, f)
PYEOF

# 4. Ensure Firefox is open and focused
echo "Launching/Focusing Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Wait for window and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | head -n1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="