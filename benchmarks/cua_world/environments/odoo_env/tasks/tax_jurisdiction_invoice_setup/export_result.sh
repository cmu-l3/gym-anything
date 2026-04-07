#!/bin/bash
# Export script for tax_jurisdiction_invoice_setup task

echo "=== Exporting tax_jurisdiction_invoice_setup Result ==="

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ ! -f /tmp/tax_setup_metadata.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/tax_task_result.json
    exit 0
fi

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
    with open('/tmp/tax_setup_metadata.json') as f:
        setup = json.load(f)
except Exception as e:
    print(f"Error loading setup data: {e}")
    sys.exit(1)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect to Odoo: {e}'}
    with open('/tmp/tax_task_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

task_start_time = 0
if os.path.exists('/tmp/task_start_time.txt'):
    with open('/tmp/task_start_time.txt', 'r') as f:
        try:
            task_start_time = int(f.read().strip())
        except:
            pass

# 1. Find the Tax
# Look for a tax created with 8.875 amount
taxes = execute('account.tax', 'search_read', 
    [[['amount', '=', 8.875], ['type_tax_use', '=', 'sale']]], 
    {'fields': ['id', 'name', 'amount', 'create_date']})

found_tax = None
tax_created_during_task = False

# Filter by time if possible, or just pick the first match
if taxes:
    # Sort by ID desc to get newest
    taxes.sort(key=lambda x: x['id'], reverse=True)
    found_tax = taxes[0]
    
    # Check creation time roughly (Odoo returns string dates)
    # We'll rely on ID being high or existence for now, verify creation time in verification logic if needed
    # But for now, just finding it is good.
    pass

# 2. Check Products for Tax Assignment
product_status = {}
for p_name, p_id in setup['products'].items():
    p_data = execute('product.template', 'read', [p_id], {'fields': ['taxes_id']})
    if p_data:
        tax_ids = p_data[0]['taxes_id']
        has_target_tax = False
        if found_tax and found_tax['id'] in tax_ids:
            has_target_tax = True
        product_status[p_name] = {
            'has_target_tax': has_target_tax,
            'tax_ids': tax_ids
        }

# 3. Find the Invoice
partner_id = setup['partner_id']
invoices = execute('account.move', 'search_read', 
    [[['partner_id', '=', partner_id], ['move_type', '=', 'out_invoice']]], 
    {'fields': ['id', 'state', 'amount_total', 'amount_tax', 'invoice_line_ids', 'create_date'], 'order': 'id desc'})

target_invoice = None
invoice_correct_lines = False
invoice_correct_tax_amount = False
invoice_posted = False

if invoices:
    target_invoice = invoices[0] # Newest
    
    # Check lines
    line_ids = target_invoice['invoice_line_ids']
    if line_ids:
        lines = execute('account.move.line', 'read', line_ids, {'fields': ['product_id', 'quantity', 'price_unit', 'tax_ids']})
        
        # Verify specific quantities
        qty_desk = 0
        qty_chair = 0
        
        desk_id = setup['products'].get('Office Standing Desk')
        chair_id = setup['products'].get('Ergonomic Task Chair')
        
        lines_have_tax = True
        
        for l in lines:
            pid = l['product_id'][0] if l['product_id'] else None
            
            # Check if line has the specific tax
            line_tax_ids = l['tax_ids']
            if found_tax and found_tax['id'] not in line_tax_ids:
                lines_have_tax = False

            # Check product types (template ID vs product ID mapping can be tricky in Odoo)
            # We will rely on checking the product name or assuming the ID setup maps correctly.
            # Odoo XMLRPC setup returned template IDs. Move lines use product.product IDs.
            # Let's check name via product_id lookup or just trust quantities if simple.
            # Better: get product name from line
            
            prod_info = execute('product.product', 'read', [pid], {'fields': ['product_tmpl_id']})
            tmpl_id = prod_info[0]['product_tmpl_id'][0]
            
            if tmpl_id == desk_id:
                qty_desk += l['quantity']
            elif tmpl_id == chair_id:
                qty_chair += l['quantity']
        
        if qty_desk == 4 and qty_chair == 6:
            invoice_correct_lines = True
            
    if target_invoice['state'] == 'posted':
        invoice_posted = True

result = {
    'task_start_time': task_start_time,
    'found_tax': found_tax,
    'product_status': product_status,
    'invoice': target_invoice,
    'invoice_analysis': {
        'correct_lines': invoice_correct_lines,
        'posted': invoice_posted,
        'lines_have_target_tax': lines_have_tax if 'lines_have_tax' in locals() else False
    }
}

with open('/tmp/tax_task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result exported to /tmp/tax_task_result.json"