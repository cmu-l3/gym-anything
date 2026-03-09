#!/bin/bash
# Setup script for vendor_bill_reconciliation task
# Creates a purchase order at the correct price and a vendor bill at an inflated price.
# The agent must find the discrepancy, correct the bill, and register payment.

echo "=== Setting up vendor_bill_reconciliation ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback: define odoo_query if not sourced
if ! type odoo_query &>/dev/null; then
    odoo_query() {
        docker exec odoo-postgres psql -U odoo "${ODOO_DB_NAME:-odoo_demo}" -t -A -c "$1" 2>/dev/null
    }
fi

take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/dataset/call_kw" 2>/dev/null || echo "000")
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null && break
    sleep 3
done
sleep 2

# Run Python setup via XML-RPC
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

# ─── Find a real vendor from demo data ───────────────────────────────────────
vendors = execute('res.partner', 'search_read',
    [[['supplier_rank', '>', 0], ['is_company', '=', True], ['active', '=', True]]],
    {'fields': ['id', 'name', 'email'], 'order': 'supplier_rank desc', 'limit': 5})

if vendors:
    # Use the first demo vendor
    vendor = vendors[0]
    vendor_id = vendor['id']
    vendor_name = vendor['name']
    print(f"Using existing vendor: {vendor_name} (id={vendor_id})")
else:
    # Create a minimal vendor
    vendor_id = execute('res.partner', 'create', [{
        'name': 'Northgate Industrial Supplies',
        'is_company': True,
        'supplier_rank': 1,
        'email': 'orders@northgate-supplies.com',
        'phone': '+1-312-555-0180',
    }])
    vendor_name = 'Northgate Industrial Supplies'
    print(f"Created vendor: {vendor_name} (id={vendor_id})")

# ─── Find a real purchasable product from demo data ──────────────────────────
products = execute('product.template', 'search_read',
    [[['purchase_ok', '=', True], ['type', 'in', ['consu', 'product']],
      ['active', '=', True], ['standard_price', '>', 0]]],
    {'fields': ['id', 'name', 'standard_price', 'uom_id'], 'limit': 10})

# Pick the first product with a meaningful price (> $10 to make discrepancy obvious)
product_tmpl = None
for p in products:
    if float(p.get('standard_price', 0)) > 10:
        product_tmpl = p
        break

if not product_tmpl:
    # Create a product if none suitable found
    tmpl_id = execute('product.template', 'create', [{
        'name': 'Industrial Safety Equipment Kit',
        'type': 'consu',
        'purchase_ok': True,
        'sale_ok': False,
        'standard_price': 245.00,
        'list_price': 320.00,
    }])
    product_tmpl = {'id': tmpl_id, 'name': 'Industrial Safety Equipment Kit', 'standard_price': 245.00}
    print(f"Created product: {product_tmpl['name']}")
else:
    print(f"Using existing product: {product_tmpl['name']} at ${product_tmpl['standard_price']:.2f}")

# Get product.product variant ID
product_products = execute('product.product', 'search_read',
    [[['product_tmpl_id', '=', product_tmpl['id']], ['active', '=', True]]],
    {'fields': ['id', 'name'], 'limit': 1})
if not product_products:
    print("ERROR: Could not find product variant", file=sys.stderr)
    sys.exit(1)
product_id = product_products[0]['id']

# ─── Calculate amounts ────────────────────────────────────────────────────────
correct_unit_price = float(product_tmpl.get('standard_price', 245.00))
correct_qty = 8
correct_total = round(correct_unit_price * correct_qty, 2)
# Inflate by ~40% to make discrepancy very clear
inflated_unit_price = round(correct_unit_price * 1.42, 2)
inflated_total = round(inflated_unit_price * correct_qty, 2)

print(f"PO correct amount: {correct_qty} x ${correct_unit_price:.2f} = ${correct_total:.2f}")
print(f"Bill inflated amount: {correct_qty} x ${inflated_unit_price:.2f} = ${inflated_total:.2f}")
print(f"Discrepancy: ${inflated_total - correct_total:.2f} overcharge")

# ─── Create Purchase Order at CORRECT price ───────────────────────────────────
try:
    po_id = execute('purchase.order', 'create', [{
        'partner_id': vendor_id,
        'date_order': date.today().strftime('%Y-%m-%d %H:%M:%S'),
        'order_line': [(0, 0, {
            'product_id': product_id,
            'product_qty': correct_qty,
            'price_unit': correct_unit_price,
            'name': product_tmpl['name'],
            'date_planned': (date.today() + timedelta(days=14)).strftime('%Y-%m-%d %H:%M:%S'),
        })],
    }])
    # Confirm the PO (state: purchase)
    execute('purchase.order', 'button_confirm', [[po_id]])
    po_data = execute('purchase.order', 'read', [[po_id]], {'fields': ['name', 'amount_total']})[0]
    print(f"Created and confirmed PO: {po_data['name']} for ${po_data['amount_total']:.2f}")
except Exception as e:
    print(f"ERROR creating PO: {e}", file=sys.stderr)
    sys.exit(1)

# ─── Create Vendor Bill at INFLATED price (the discrepancy to find+fix) ───────
try:
    bill_id = execute('account.move', 'create', [{
        'move_type': 'in_invoice',
        'partner_id': vendor_id,
        'invoice_date': date.today().strftime('%Y-%m-%d'),
        'ref': f'INV-{po_data["name"]}-2024-0391',
        'narration': f'Vendor invoice referencing purchase order {po_data["name"]}. Please verify against PO before posting.',
        'invoice_line_ids': [(0, 0, {
            'product_id': product_id,
            'quantity': correct_qty,
            'price_unit': inflated_unit_price,
            'name': product_tmpl['name'],
        })],
    }])
    bill_data = execute('account.move', 'read', [[bill_id]], {'fields': ['name', 'amount_total']})[0]
    print(f"Created vendor bill: {bill_data['name']} for ${bill_data['amount_total']:.2f} (INFLATED)")
except Exception as e:
    print(f"ERROR creating bill: {e}", file=sys.stderr)
    sys.exit(1)

# ─── Save setup metadata ──────────────────────────────────────────────────────
setup_data = {
    'vendor_id': vendor_id,
    'vendor_name': vendor_name,
    'product_id': product_id,
    'product_name': product_tmpl['name'],
    'po_id': po_id,
    'po_name': po_data['name'],
    'bill_id': bill_id,
    'bill_name': bill_data['name'],
    'correct_amount': correct_total,
    'inflated_amount': inflated_total,
    'correct_unit_price': correct_unit_price,
    'inflated_unit_price': inflated_unit_price,
    'quantity': correct_qty,
}
with open('/tmp/vendor_bill_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print("\n=== Setup Summary ===")
print(f"Vendor:      {vendor_name}")
print(f"PO:          {po_data['name']} at ${correct_total:.2f} (CORRECT)")
print(f"Bill:        {bill_data['name']} at ${inflated_total:.2f} (WRONG - overcharge by ${inflated_total - correct_total:.2f})")
print("Agent task: Find bill, correct to PO amount, post, register payment")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Python setup script failed!"
    exit 1
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Write a desktop note to orient the agent
cat > /home/ga/Desktop/task_instructions.txt << 'TASKEOF'
TASK: Vendor Bill Reconciliation

The Accounts Payable department has flagged a discrepancy: a vendor bill has
been received with an amount that does not match the corresponding purchase
order. Your job:

1. Log into Odoo: http://localhost:8069
   Email: admin@example.com | Password: admin | Database: odoo_demo

2. Navigate to Accounting > Vendors > Bills and find the bill with a
   discrepancy (the bill amount is higher than the purchase order amount).

3. Open the bill and compare its amount with the linked purchase order.

4. Edit the bill to correct the unit price/amount to match the purchase order.

5. Post (validate) the corrected bill.

6. Register the full payment for the bill.
TASKEOF
chmod 644 /home/ga/Desktop/task_instructions.txt

# Ensure Firefox is open at Odoo
FIREFOX_PID=$(pgrep -f firefox 2>/dev/null | head -1)
if [ -z "$FIREFOX_PID" ]; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &" 2>/dev/null
    sleep 5
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Setup data saved to /tmp/vendor_bill_setup.json"
