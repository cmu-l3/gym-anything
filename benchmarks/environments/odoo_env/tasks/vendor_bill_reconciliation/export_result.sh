#!/bin/bash
# Export script for vendor_bill_reconciliation task
# Queries the current state of the vendor bill after agent work.

echo "=== Exporting vendor_bill_reconciliation Result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Check setup data exists
if [ ! -f /tmp/vendor_bill_setup.json ]; then
    echo "ERROR: Setup data not found at /tmp/vendor_bill_setup.json"
    cat > /tmp/vendor_bill_reconciliation_result.json << 'EOF'
{"error": "setup_data_missing", "passed": false, "score": 0}
EOF
    exit 0
fi

# Use Python to query Odoo via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

# Load setup data
try:
    with open('/tmp/vendor_bill_setup.json') as f:
        setup = json.load(f)
except Exception as e:
    result = {'error': f'Cannot load setup data: {e}'}
    with open('/tmp/vendor_bill_reconciliation_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect to Odoo: {e}', **setup}
    with open('/tmp/vendor_bill_reconciliation_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

vendor_id = setup['vendor_id']
bill_id = setup['bill_id']
expected_amount = setup['correct_amount']

# Query the specific bill we created
try:
    bills = execute('account.move', 'read', [[bill_id]],
        {'fields': ['id', 'name', 'amount_total', 'amount_residual',
                    'state', 'payment_state', 'partner_id',
                    'invoice_date', 'line_ids']})
    bill = bills[0] if bills else None
except Exception as e:
    bill = None
    print(f"Warning: could not query bill {bill_id}: {e}", file=sys.stderr)

# Also query ALL vendor bills for this vendor (to catch if agent corrected a different bill)
try:
    all_vendor_bills = execute('account.move', 'search_read',
        [[['partner_id', '=', vendor_id], ['move_type', '=', 'in_invoice']]],
        {'fields': ['id', 'name', 'amount_total', 'state', 'payment_state'],
         'order': 'id desc'})
except Exception as e:
    all_vendor_bills = []

# Find any bill that's been paid for this vendor (agent may have created a new one)
paid_bills = [b for b in all_vendor_bills if b.get('payment_state') in ['paid', 'in_payment']]
posted_correct_bills = [b for b in all_vendor_bills
                        if b.get('state') == 'posted'
                        and abs(b.get('amount_total', 0) - expected_amount) / max(expected_amount, 1) < 0.05]

# Task start timestamp for new-work detection
task_start = 0
try:
    with open('/tmp/task_start_timestamp') as f:
        task_start = int(f.read().strip())
except Exception:
    pass

result = {
    'task': 'vendor_bill_reconciliation',
    'vendor_id': vendor_id,
    'vendor_name': setup['vendor_name'],
    'bill_id': bill_id,
    'bill_amount': bill['amount_total'] if bill else None,
    'bill_state': bill['state'] if bill else 'unknown',
    'bill_payment_state': bill['payment_state'] if bill else 'not_paid',
    'bill_partner_id': bill['partner_id'][0] if (bill and isinstance(bill.get('partner_id'), list)) else vendor_id,
    'expected_amount': expected_amount,
    'inflated_amount': setup['inflated_amount'],
    'all_vendor_bills_count': len(all_vendor_bills),
    'paid_bills_count': len(paid_bills),
    'posted_correct_amount_bills_count': len(posted_correct_bills),
    # Check if any bill for this vendor has the correct amount AND is paid
    'any_bill_correct_and_paid': any(
        abs(b.get('amount_total', 0) - expected_amount) / max(expected_amount, 1) < 0.05
        and b.get('payment_state') in ['paid', 'in_payment']
        for b in all_vendor_bills
    ),
    'task_start': task_start,
    'export_timestamp': __import__('datetime').datetime.now().isoformat(),
}

with open('/tmp/vendor_bill_reconciliation_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Bill state: {result['bill_state']} | Payment: {result['bill_payment_state']}")
print(f"Bill amount: ${result['bill_amount']:.2f} | Expected: ${result['expected_amount']:.2f}")
print(f"Vendor bills for this vendor: {result['all_vendor_bills_count']}")
PYEOF

echo "=== Export Complete ==="
