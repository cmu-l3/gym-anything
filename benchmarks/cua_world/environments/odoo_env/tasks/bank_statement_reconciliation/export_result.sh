#!/bin/bash
# Export script for bank_statement_reconciliation
# Queries the payment status of the invoices created during setup.

echo "=== Exporting bank_statement_reconciliation result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if setup data exists
if [ ! -f /tmp/bank_reconciliation_setup.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/task_result.json
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    with open('/tmp/bank_reconciliation_setup.json') as f:
        setup = json.load(f)
except Exception as e:
    print(f"Error loading setup: {e}")
    sys.exit(0)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

results = {
    'documents': {},
    'bank_fee_found': False,
    'statements_found': False
}

# 1. Check Invoice/Bill Payment Status
doc_ids = [setup['invoice_1'], setup['invoice_2'], setup['bill_1'], setup['bill_2']]
docs = execute('account.move', 'read', [doc_ids], {'fields': ['id', 'payment_state', 'name', 'amount_total']})

for doc in docs:
    key = next((k for k, v in setup.items() if v == doc['id']), str(doc['id']))
    results['documents'][key] = {
        'id': doc['id'],
        'state': doc['payment_state'], # 'paid' or 'in_payment' is good
        'amount': doc['amount_total']
    }

# 2. Check for Bank Fee
# Look for a journal entry created recently with ~35.00 amount
# Note: Bank fees are often created as account.move with journal_id = Bank
# We assume the agent created a move line for 35.00 or -35.00
moves = execute('account.move.line', 'search_read', 
    [[['credit', '=', 35.00], ['parent_state', '=', 'posted']]], 
    {'fields': ['id', 'name', 'account_id', 'date'], 'limit': 5})

# Also check debit if they did it that way
if not moves:
    moves = execute('account.move.line', 'search_read', 
        [[['debit', '=', 35.00], ['parent_state', '=', 'posted']]], 
        {'fields': ['id', 'name', 'account_id', 'date'], 'limit': 5})

results['bank_fee_found'] = len(moves) > 0

# 3. Check for Bank Statements
# Odoo 14-16 uses account.bank.statement, Odoo 17 might differ but usually same model
statements = execute('account.bank.statement', 'search_read',
    [], {'fields': ['id', 'name', 'date', 'state'], 'limit': 5})

results['statements_found'] = len(statements) > 0
results['statement_details'] = statements

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)

print("Export completed.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="