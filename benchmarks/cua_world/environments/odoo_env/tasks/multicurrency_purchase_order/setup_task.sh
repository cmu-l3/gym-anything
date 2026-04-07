#!/bin/bash
# Setup script for multicurrency_purchase_order task
# 1. Activates EUR currency and sets exchange rate
# 2. Creates the two required products
# 3. Ensures country data is available

echo "=== Setting up multicurrency_purchase_order ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    if curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null; then
        break
    fi
    sleep 3
done
sleep 2

# Execute setup via Python/XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import date

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

# 1. Activate EUR Currency
print("Configuring EUR currency...")
eur_currency = execute('res.currency', 'search_read', 
    [[['name', '=', 'EUR']]], 
    {'fields': ['id', 'active']})

if eur_currency:
    eur_id = eur_currency[0]['id']
    if not eur_currency[0]['active']:
        execute('res.currency', 'write', [[eur_id], {'active': True}])
        print(f"Activated EUR (id={eur_id})")
    
    # Set exchange rate: 1 EUR = 1.0850 USD
    # Odoo stores rate as 1 unit of base currency = X units of foreign currency
    # OR 1 unit of foreign = X units of base, depending on config.
    # Default Odoo often uses inverse: 1 USD = 0.9217 EUR
    # We will create a rate for today
    today = date.today().strftime('%Y-%m-%d')
    execute('res.currency.rate', 'create', [{
        'currency_id': eur_id,
        'name': today,
        'rate': 0.9217, # 1 USD = 0.9217 EUR (approx 1 EUR = 1.085 USD)
        'company_id': 1
    }])
else:
    print("ERROR: EUR currency not found in database", file=sys.stderr)
    sys.exit(1)

# 2. Create Products
products_data = [
    {
        'name': 'Precision Bearing Assembly Type-K', 
        'standard_price': 46.11, # ~42.50 EUR
        'list_price': 60.00
    },
    {
        'name': 'Industrial Servo Motor Controller', 
        'standard_price': 205.07, # ~189.00 EUR
        'list_price': 250.00
    }
]

created_products = {}

for p in products_data:
    # Check if exists
    existing = execute('product.template', 'search_read', 
        [[['name', '=', p['name']]]], 
        {'fields': ['id']})
    
    if existing:
        pid = existing[0]['id']
        print(f"Product exists: {p['name']} (id={pid})")
    else:
        pid = execute('product.template', 'create', [{
            'name': p['name'],
            'type': 'product',
            'purchase_ok': True,
            'sale_ok': True,
            'standard_price': p['standard_price'],
            'list_price': p['list_price']
        }])
        print(f"Created product: {p['name']} (id={pid})")
    
    # Get variant ID
    variants = execute('product.product', 'search_read',
        [[['product_tmpl_id', '=', pid]]],
        {'fields': ['id']})
    created_products[p['name']] = variants[0]['id']

# 3. Verify Germany exists
germany = execute('res.country', 'search_read',
    [[['code', '=', 'DE']]],
    {'fields': ['id', 'name']})
if not germany:
    print("ERROR: Germany not found in res.country", file=sys.stderr)
    # Typically exists in demo data, but if not, fail setup
    sys.exit(1)

# Save Setup Data
setup_info = {
    'eur_currency_id': eur_id,
    'products': created_products,
    'germany_country_id': germany[0]['id']
}

with open('/tmp/multicurrency_po_setup.json', 'w') as f:
    json.dump(setup_info, f, indent=2)

print("Setup complete. Data saved to /tmp/multicurrency_po_setup.json")
PYEOF

echo "=== Setup complete ==="