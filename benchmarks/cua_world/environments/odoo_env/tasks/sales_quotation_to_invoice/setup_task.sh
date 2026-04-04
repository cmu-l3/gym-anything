#!/bin/bash
# Setup script for sales_quotation_to_invoice task
# Creates a customer "Meridian Pacific Group" and two products that the agent must order.

echo "=== Setting up sales_quotation_to_invoice ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

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

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import date, timedelta

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

CUSTOMER_NAME = 'Meridian Pacific Group'

# ─── Create or find the customer ─────────────────────────────────────────────
existing = execute('res.partner', 'search_read',
    [[['name', '=', CUSTOMER_NAME], ['is_company', '=', True]]],
    {'fields': ['id', 'name'], 'limit': 1})

if existing:
    customer_id = existing[0]['id']
    print(f"Using existing customer: {CUSTOMER_NAME} (id={customer_id})")
else:
    customer_id = execute('res.partner', 'create', [{
        'name': CUSTOMER_NAME,
        'is_company': True,
        'customer_rank': 1,
        'email': 'purchasing@meridianpacific.example.com',
        'phone': '+1-503-555-0174',
        'city': 'Portland',
        'country_id': 233,  # USA
    }])
    print(f"Created customer: {CUSTOMER_NAME} (id={customer_id})")

# ─── Product definitions ──────────────────────────────────────────────────────
PRODUCTS = [
    {
        'name': 'Standing Desk Pro - Height Adjustable',
        'default_code': 'DESK-STAND-PRO',
        'type': 'consu',
        'list_price': 649.00,
        'standard_price': 310.00,
        'qty': 15,
    },
    {
        'name': 'Executive High-Back Chair',
        'default_code': 'CHAIR-EXEC-HB',
        'type': 'consu',
        'list_price': 425.00,
        'standard_price': 195.00,
        'qty': 8,
    },
]

setup_products = []
for prod_def in PRODUCTS:
    # Check if product already exists
    existing_prod = execute('product.template', 'search_read',
        [[['name', '=', prod_def['name']], ['active', '=', True]]],
        {'fields': ['id', 'name', 'list_price'], 'limit': 1})

    if existing_prod:
        tmpl_id = existing_prod[0]['id']
        list_price = float(existing_prod[0].get('list_price', prod_def['list_price']))
        print(f"Using existing product: {prod_def['name']} (id={tmpl_id})")
    else:
        tmpl_id = execute('product.template', 'create', [{
            'name': prod_def['name'],
            'default_code': prod_def['default_code'],
            'type': prod_def['type'],
            'sale_ok': True,
            'purchase_ok': True,
            'list_price': prod_def['list_price'],
            'standard_price': prod_def['standard_price'],
        }])
        list_price = prod_def['list_price']
        print(f"Created product: {prod_def['name']} (id={tmpl_id})")

    # Get product.product variant ID
    variants = execute('product.product', 'search_read',
        [[['product_tmpl_id', '=', tmpl_id], ['active', '=', True]]],
        {'fields': ['id', 'name'], 'limit': 1})
    product_id = variants[0]['id'] if variants else None

    setup_products.append({
        'tmpl_id': tmpl_id,
        'product_id': product_id,
        'name': prod_def['name'],
        'list_price': list_price,
        'qty': prod_def['qty'],
        'expected_subtotal': round(list_price * prod_def['qty'], 2),
    })

# ─── Find or create 30-day payment terms ─────────────────────────────────────
payment_terms = execute('account.payment.term', 'search_read',
    [[['active', '=', True]]],
    {'fields': ['id', 'name'], 'limit': 20})

pt_30 = None
for pt in payment_terms:
    name_lower = pt['name'].lower()
    if '30' in name_lower and ('day' in name_lower or 'net' in name_lower or 'days' in name_lower):
        pt_30 = pt
        break
if not pt_30 and payment_terms:
    pt_30 = payment_terms[0]  # fallback to first available

print(f"Payment terms: {pt_30['name'] if pt_30 else 'None found'}")

# ─── Calculate expected totals ────────────────────────────────────────────────
expected_total = sum(p['expected_subtotal'] for p in setup_products)

# ─── Save setup data ──────────────────────────────────────────────────────────
setup_data = {
    'customer_id': customer_id,
    'customer_name': CUSTOMER_NAME,
    'products': setup_products,
    'payment_terms_id': pt_30['id'] if pt_30 else None,
    'payment_terms_name': pt_30['name'] if pt_30 else None,
    'expected_total': expected_total,
}
with open('/tmp/sales_quotation_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print(f"\n=== Setup Summary ===")
print(f"Customer: {CUSTOMER_NAME}")
for p in setup_products:
    print(f"  Product: {p['name']} x{p['qty']} @ ${p['list_price']:.2f} = ${p['expected_subtotal']:.2f}")
print(f"  Expected total: ${expected_total:.2f}")
print(f"  Payment terms: {pt_30['name'] if pt_30 else 'N/A'}")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Python setup script failed!"
    exit 1
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is open at Odoo Sales
FIREFOX_PID=$(pgrep -f firefox 2>/dev/null | head -1)
if [ -z "$FIREFOX_PID" ]; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/odoo/sales' &" 2>/dev/null
    sleep 5
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Setup data: /tmp/sales_quotation_setup.json"
