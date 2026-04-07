#!/bin/bash
# Setup script for customer_credit_note_refund task
# Creates a paid invoice for "Northstar Industrial Solutions" and a return request file.

echo "=== Setting up customer_credit_note_refund ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Create Desktop directory if it doesn't exist
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Python script to populate Odoo data via XML-RPC
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
        print(f"Error connecting to Odoo: {e}", file=sys.stderr)
        return None, None

uid, models = get_connection()
if not uid:
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Create Customer
customer_name = "Northstar Industrial Solutions"
existing_partner = execute('res.partner', 'search_read', 
    [[['name', '=', customer_name]]], 
    {'fields': ['id'], 'limit': 1})

if existing_partner:
    partner_id = existing_partner[0]['id']
else:
    partner_id = execute('res.partner', 'create', [{
        'name': customer_name,
        'is_company': True,
        'email': 'accounts@northstar-ind.example.com',
        'street': '742 Evergreen Terrace',
        'city': 'Springfield',
        'zip': '90210'
    }])
print(f"Customer ID: {partner_id}")

# 2. Create Products
products = [
    {'name': 'Industrial Safety Helmet', 'price': 45.00, 'code': 'SAFE-HELM'},
    {'name': 'High-Visibility Safety Vest', 'price': 32.00, 'code': 'SAFE-VEST'}
]

product_ids = {}
for p in products:
    existing = execute('product.product', 'search_read', 
        [[['name', '=', p['name']]]], 
        {'fields': ['id'], 'limit': 1})
    
    if existing:
        pid = existing[0]['id']
        # Ensure price is correct
        execute('product.product', 'write', [[pid], {'list_price': p['price']}])
    else:
        pid = execute('product.product', 'create', [{
            'name': p['name'],
            'default_code': p['code'],
            'list_price': p['price'],
            'type': 'consu', # Consumable to avoid inventory warnings for this task
        }])
    product_ids[p['name']] = pid
    print(f"Product {p['name']} ID: {pid}")

# 3. Create Invoice (Paid)
# We create an invoice directly (account.move) rather than via Sales Order to simplify dependencies,
# simulating a direct invoice or an imported historical order.
invoice_id = execute('account.move', 'create', [{
    'move_type': 'out_invoice',
    'partner_id': partner_id,
    'invoice_date': time.strftime('%Y-%m-%d'),
    'date': time.strftime('%Y-%m-%d'),
    'invoice_line_ids': [
        (0, 0, {
            'product_id': product_ids['Industrial Safety Helmet'],
            'quantity': 20,
            'price_unit': 45.00,
        }),
        (0, 0, {
            'product_id': product_ids['High-Visibility Safety Vest'],
            'quantity': 30,
            'price_unit': 32.00,
        })
    ]
}])
print(f"Draft Invoice ID: {invoice_id}")

# Post the invoice
execute('account.move', 'action_post', [[invoice_id]])
print("Invoice Posted")

# Register Payment
# Get the account.move record to find amount and other details
invoice = execute('account.move', 'read', [[invoice_id]], ['amount_residual', 'name'])[0]

# Create payment register wizard context
# Note: In Odoo 16/17, payment registration is often done via account.payment.register wizard
payment_register = execute('account.payment.register', 'create', [{
    # Context is usually passed in args for defaults, but here we set explicitly if possible
    # or rely on default logic. simpler to create payment directly linked to invoice.
    'payment_date': time.strftime('%Y-%m-%d'),
    'amount': invoice['amount_residual'],
    'payment_method_line_id': execute('account.payment.method.line', 'search', [[['payment_type', '=', 'inbound']]], {'limit': 1})[0],
}], {'context': {'active_model': 'account.move', 'active_ids': [invoice_id]}})

# The wizard 'create_payments' method does the actual work
execute('account.payment.register', 'action_create_payments', [[payment_register]])
print("Payment Registered")

# Verify invoice status
final_inv = execute('account.move', 'read', [[invoice_id]], ['payment_state'])[0]
print(f"Invoice Payment State: {final_inv['payment_state']}")

# Save setup data
setup_data = {
    'partner_id': partner_id,
    'invoice_id': invoice_id,
    'product_map': product_ids,
    'expected_refund_total': (8 * 45.00) + (12 * 32.00)
}

with open('/tmp/credit_note_setup.json', 'w') as f:
    json.dump(setup_data, f)

PYEOF

# Create the return request text file on the Desktop
cat > /home/ga/Desktop/return_request.txt << 'EOF'
RETURN REQUEST
------------------------------------------------
Customer: Northstar Industrial Solutions
Date: Today

Reference: Recent Order

Items to Return:
1. Industrial Safety Helmet
   - Quantity: 8 units
   - Reason: Defective strap mechanism in batch

2. High-Visibility Safety Vest
   - Quantity: 12 units
   - Reason: Incorrect size shipped (L sent instead of XL)

ACTION REQUIRED:
Please issue a credit note (refund) for these items against the original invoice.
Ensure the credit note is validated and the refund payment is registered.
EOF

chown ga:ga /home/ga/Desktop/return_request.txt

# Ensure Firefox is started and focused (standard Odoo task setup)
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="