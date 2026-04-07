#!/bin/bash
# Setup script for bank_statement_reconciliation task
# Creates:
# 1. Two Customers with open Invoices
# 2. Two Vendors with open Bills
# 3. A text file on Desktop with bank statement data

echo "=== Setting up bank_statement_reconciliation ==="

# Record task start time
date +%s > /tmp/task_start_timestamp

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Create Desktop file
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/bank_statement_august.txt << 'EOF'
=== BANK STATEMENT — August 2024 ===
Account: Main Operating Account
Statement Date: 08/31/2024

Date        | Description                          | Amount
------------|--------------------------------------|------------
08/05/2024  | Payment received: Alpine Ridge Consulting | +4,250.00
08/12/2024  | Payment received: Coastal Bay Solutions   | +2,780.00
08/18/2024  | Payment to: Summit Supply Co             | -1,950.00
08/25/2024  | Payment to: Pacific Materials Inc         | -3,100.00
08/31/2024  | Bank Service Fee                         | -35.00

Starting Balance: 12,500.00
Ending Balance:   14,445.00
EOF
chown ga:ga /home/ga/Desktop/bank_statement_august.txt

# Run Python setup via XML-RPC to create data
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

# ─── 1. Create Partners ──────────────────────────────────────────────────────
partners = [
    {'name': 'Alpine Ridge Consulting', 'is_company': True, 'customer_rank': 1, 'supplier_rank': 0},
    {'name': 'Coastal Bay Solutions', 'is_company': True, 'customer_rank': 1, 'supplier_rank': 0},
    {'name': 'Summit Supply Co', 'is_company': True, 'customer_rank': 0, 'supplier_rank': 1},
    {'name': 'Pacific Materials Inc', 'is_company': True, 'customer_rank': 0, 'supplier_rank': 1},
]

partner_ids = {}
for p in partners:
    # Check if exists
    existing = execute('res.partner', 'search_read', [[['name', '=', p['name']]]], {'fields': ['id']})
    if existing:
        pid = existing[0]['id']
    else:
        pid = execute('res.partner', 'create', [p])
    partner_ids[p['name']] = pid
    print(f"Partner: {p['name']} (id={pid})")

# ─── 2. Create Products ──────────────────────────────────────────────────────
products = [
    {'name': 'IT Consulting Services', 'list_price': 850.00, 'type': 'service'},
    {'name': 'Marketing Strategy Package', 'list_price': 695.00, 'type': 'service'},
    {'name': 'Office Supplies Batch', 'standard_price': 1950.00, 'type': 'consu'},
    {'name': 'Raw Material - Grade A', 'standard_price': 3100.00, 'type': 'product'},
]

product_ids = {}
for prod in products:
    existing = execute('product.product', 'search_read', [[['name', '=', prod['name']]]], {'fields': ['id']})
    if existing:
        pid = existing[0]['id']
    else:
        # Create template then find product (simple way)
        tmpl_id = execute('product.template', 'create', [{
            'name': prod['name'],
            'type': prod['type'],
            'list_price': prod.get('list_price', 1.0),
            'standard_price': prod.get('standard_price', 1.0),
        }])
        pid = execute('product.product', 'search_read', [[['product_tmpl_id', '=', tmpl_id]]], {'fields': ['id']})[0]['id']
    product_ids[prod['name']] = pid

# ─── 3. Create Invoices and Bills ────────────────────────────────────────────
# We need dates in the past so they look like they need reconciliation
invoice_date = (date.today() - timedelta(days=25)).isoformat()

documents = [
    # Customer Invoice 1: Alpine Ridge (+4250.00)
    {
        'type': 'out_invoice', # Customer Invoice
        'partner_id': partner_ids['Alpine Ridge Consulting'],
        'lines': [{'product_id': product_ids['IT Consulting Services'], 'quantity': 5, 'price_unit': 850.00}],
        'key': 'invoice_1'
    },
    # Customer Invoice 2: Coastal Bay (+2780.00)
    {
        'type': 'out_invoice',
        'partner_id': partner_ids['Coastal Bay Solutions'],
        'lines': [{'product_id': product_ids['Marketing Strategy Package'], 'quantity': 4, 'price_unit': 695.00}],
        'key': 'invoice_2'
    },
    # Vendor Bill 1: Summit Supply (-1950.00)
    {
        'type': 'in_invoice', # Vendor Bill
        'partner_id': partner_ids['Summit Supply Co'],
        'lines': [{'product_id': product_ids['Office Supplies Batch'], 'quantity': 1, 'price_unit': 1950.00}],
        'key': 'bill_1'
    },
    # Vendor Bill 2: Pacific Materials (-3100.00)
    {
        'type': 'in_invoice',
        'partner_id': partner_ids['Pacific Materials Inc'],
        'lines': [{'product_id': product_ids['Raw Material - Grade A'], 'quantity': 1, 'price_unit': 3100.00}],
        'key': 'bill_2'
    }
]

setup_data = {}

for doc in documents:
    move_lines = []
    # Invoice line
    for line in doc['lines']:
        move_lines.append((0, 0, {
            'product_id': line['product_id'],
            'quantity': line['quantity'],
            'price_unit': line['price_unit'],
        }))
    
    move_id = execute('account.move', 'create', [{
        'move_type': doc['type'],
        'partner_id': doc['partner_id'],
        'invoice_date': invoice_date,
        'invoice_line_ids': move_lines,
    }])
    
    # Post the invoice/bill
    execute('account.move', 'action_post', [[move_id]])
    
    print(f"Created {doc['type']} id={move_id} for partner {doc['partner_id']}")
    setup_data[doc['key']] = move_id

# Save IDs for verification
with open('/tmp/bank_reconciliation_setup.json', 'w') as f:
    json.dump(setup_data, f)

print("Setup data saved to /tmp/bank_reconciliation_setup.json")
PYEOF

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="