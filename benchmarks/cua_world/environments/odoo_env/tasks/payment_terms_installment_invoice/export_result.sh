#!/bin/bash
# Export script for payment_terms_installment_invoice
# Extracts payment terms, invoice status, and journal items to JSON.

echo "=== Exporting Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to query Odoo state
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

# Helper for JSON serialization of dates
class DateTimeEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, (datetime.date, datetime.datetime)):
            return obj.isoformat()
        return super(DateTimeEncoder, self).default(obj)

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    # If Odoo is down, we can't verify
    print(f"Error connecting to Odoo: {e}")
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({"error": "connection_failed"}, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# --- 1. Load Setup Data ---
try:
    with open('/tmp/payment_terms_setup.json', 'r') as f:
        setup = json.load(f)
        partner_id = setup.get('partner_id')
except:
    partner_id = None

# --- 2. Check Payment Term Creation ---
# Look for term with "3-Installment" in name created recently
# We don't filter by create_date strictly here to allow flexibility, but we check name
payment_terms = execute('account.payment.term', 'search_read', 
    [[['name', 'ilike', '3-Installment']]], 
    {'fields': ['id', 'name', 'line_ids']})

term_data = []
for term in payment_terms:
    # Get lines for this term
    lines = execute('account.payment.term.line', 'read', 
        [term['line_ids']], 
        {'fields': ['value', 'value_amount', 'days', 'delay_type']}) # value='percent'/'balance', value_amount=%, days=days
    
    term_data.append({
        'id': term['id'],
        'name': term['name'],
        'lines': lines
    })

# --- 3. Check Invoice Creation ---
# Look for invoice for Pinnacle Industries
invoice_domain = [['move_type', '=', 'out_invoice']]
if partner_id:
    invoice_domain.append(['partner_id', '=', partner_id])
else:
    invoice_domain.append(['partner_id.name', 'ilike', 'Pinnacle'])

invoices = execute('account.move', 'search_read', 
    [invoice_domain], 
    {'fields': ['id', 'name', 'state', 'invoice_payment_term_id', 'amount_total', 'invoice_date', 'create_date'], 'order': 'id desc', 'limit': 1})

invoice_data = None
receivables_data = []

if invoices:
    inv = invoices[0]
    invoice_data = inv
    
    # Get Journal Items (Receivables) to verify installments
    # Account type 'asset_receivable' (in Odoo 15+ account types are slightly different, checking by account internal type or just line properties)
    # We look for lines in this move that have an account with type 'receivable'
    
    move_lines = execute('account.move.line', 'search_read',
        [[['move_id', '=', inv['id']], ['account_id.account_type', '=', 'asset_receivable'], ['exclude_from_invoice_tab', '=', True]]],
        {'fields': ['name', 'debit', 'credit', 'date_maturity', 'account_id']})
        
    # If Odoo version < 14, account_type might be different, but 'asset_receivable' is standard in newer Odoo
    # Fallback if empty: search all lines and check account type manually if needed
    if not move_lines:
         move_lines = execute('account.move.line', 'search_read',
            [[['move_id', '=', inv['id']], ['debit', '>', 0]]],
            {'fields': ['name', 'debit', 'date_maturity', 'account_id']})

    receivables_data = move_lines

# --- 4. Timestamps ---
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = float(f.read().strip())
except:
    task_start = 0

result = {
    "task_start_timestamp": task_start,
    "payment_terms_found": term_data,
    "invoice_found": invoice_data,
    "receivables_lines": receivables_data,
    "setup_partner_id": partner_id
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, cls=DateTimeEncoder, indent=2)

print("Export complete.")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true