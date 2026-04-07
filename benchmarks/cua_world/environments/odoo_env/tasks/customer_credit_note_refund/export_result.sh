#!/bin/bash
# Export script for customer_credit_note_refund task

echo "=== Exporting Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check for setup file
if [ ! -f /tmp/credit_note_setup.json ]; then
    echo '{"error": "Setup file missing"}' > /tmp/task_result.json
    exit 1
fi

# 3. Python script to query Odoo and extract results
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

# Load setup data
try:
    with open('/tmp/credit_note_setup.json', 'r') as f:
        setup = json.load(f)
except Exception as e:
    print(f"Error loading setup: {e}")
    sys.exit(1)

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
    except:
        return None, None

uid, models = get_connection()
if not uid:
    # Save partial result indicating connection failure
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': 'Odoo connection failed'}, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Get original invoice to exclude it from search
original_invoice_id = setup['invoice_id']
partner_id = setup['partner_id']
task_start_timestamp = 0
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        task_start_timestamp = float(f.read().strip())
except:
    pass

# Search for Credit Notes (out_refund) for this partner
# We want records created AFTER the task started (approximately)
# Since Odoo dates are sometimes just dates or UTC datetimes, easiest is to check ID > original invoice ID
# assuming sequential IDs, or check create_date if needed.
# Reliable check: move_type='out_refund' AND partner_id=target AND id > original_invoice_id

credit_notes = execute('account.move', 'search_read', 
    [[
        ['move_type', '=', 'out_refund'], 
        ['partner_id', '=', partner_id],
        ['id', '>', original_invoice_id]
    ]], 
    {'fields': ['id', 'name', 'state', 'payment_state', 'amount_total', 'invoice_line_ids', 'create_date']})

results = {
    'credit_note_found': False,
    'count': len(credit_notes),
    'credit_note': None
}

if credit_notes:
    # Take the most recent one if multiple (though likely only one)
    # Sort by ID descending
    cn = sorted(credit_notes, key=lambda x: x['id'], reverse=True)[0]
    
    # Fetch line details
    line_ids = cn['invoice_line_ids']
    lines = []
    if line_ids:
        lines_data = execute('account.move.line', 'read', [line_ids], ['product_id', 'quantity', 'price_unit', 'price_subtotal'])
        for l in lines_data:
            # product_id is [id, name] tuple
            p_name = l['product_id'][1] if l['product_id'] else "Unknown"
            lines.append({
                'product_name': p_name,
                'quantity': l['quantity'],
                'price_unit': l['price_unit'],
                'subtotal': l['price_subtotal']
            })

    results['credit_note_found'] = True
    results['credit_note'] = {
        'id': cn['id'],
        'state': cn['state'],
        'payment_state': cn['payment_state'],
        'amount_total': cn['amount_total'],
        'lines': lines
    }

# Write results
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)

PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json