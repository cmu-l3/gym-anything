#!/bin/bash
# Export script for fiscal_position_tax_exempt task
# Queries Odoo for the fiscal position, customer, and sales order.

echo "=== Exporting fiscal_position_tax_exempt results ==="

# Record end time
date +%s > /tmp/task_end_time.txt

# Capture final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Run Python script to extract verification data
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
    with open('/tmp/fiscal_position_setup.json') as f:
        setup = json.load(f)
except FileNotFoundError:
    print("ERROR: Setup file not found", file=sys.stderr)
    setup = {}

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Connection failed: {e}", file=sys.stderr)
    # Write partial result
    with open('/tmp/fiscal_position_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

results = {
    "setup": setup,
    "fiscal_position_found": False,
    "tax_mapping_correct": False,
    "customer_found": False,
    "customer_fp_correct": False,
    "order_found": False,
    "order_products_correct": False,
    "order_tax_zero": False,
    "details": {}
}

# 1. Check Fiscal Position
# Look for something resembling "Tax Exempt" or "Nonprofit"
fp_candidates = execute('account.fiscal.position', 'search_read',
    [[['name', 'ilike', 'Exempt']]],
    {'fields': ['id', 'name', 'tax_ids']})

if not fp_candidates:
    # Try searching for "Nonprofit"
    fp_candidates = execute('account.fiscal.position', 'search_read',
        [[['name', 'ilike', 'Nonprofit']]],
        {'fields': ['id', 'name', 'tax_ids']})

target_fp = None
if fp_candidates:
    results['fiscal_position_found'] = True
    target_fp = fp_candidates[0] # Take the first match
    results['details']['fiscal_position_name'] = target_fp['name']
    
    # Check tax mapping
    # tax_ids is a One2many to account.fiscal.position.tax
    # We need to check if the default tax is mapped to None/False
    if target_fp['tax_ids']:
        mapping_ids = target_fp['tax_ids']
        mappings = execute('account.fiscal.position.tax', 'read',
            [mapping_ids],
            {'fields': ['tax_src_id', 'tax_dest_id']})
        
        default_tax_id = setup.get('default_tax_id')
        
        for m in mappings:
            src_id = m['tax_src_id'][0] if m['tax_src_id'] else None
            dest_id = m['tax_dest_id'] # Should be False or empty
            
            if src_id == default_tax_id:
                if not dest_id:
                    results['tax_mapping_correct'] = True
                    results['details']['mapping_status'] = "Correct: Mapped to None"
                else:
                    results['details']['mapping_status'] = f"Incorrect: Mapped to {dest_id}"
                break
else:
    results['details']['fiscal_position'] = "Not Found"

# 2. Check Customer
cust_candidates = execute('res.partner', 'search_read',
    [[['name', 'ilike', 'Green Earth Foundation']]],
    {'fields': ['id', 'name', 'property_account_position_id', 'email', 'is_company']})

target_customer = None
if cust_candidates:
    results['customer_found'] = True
    target_customer = cust_candidates[0]
    results['details']['customer_name'] = target_customer['name']
    results['details']['is_company'] = target_customer['is_company']
    
    # Check assigned fiscal position
    # property_account_position_id returns [id, name] or False
    assigned_fp = target_customer['property_account_position_id']
    
    if assigned_fp and target_fp and assigned_fp[0] == target_fp['id']:
        results['customer_fp_correct'] = True
        results['details']['customer_fp'] = assigned_fp[1]
    elif assigned_fp:
        results['details']['customer_fp'] = assigned_fp[1]
        results['details']['expected_fp'] = target_fp['name'] if target_fp else "Tax Exempt..."
    else:
        results['details']['customer_fp'] = "None"

# 3. Check Sales Order
if target_customer:
    orders = execute('sale.order', 'search_read',
        [[['partner_id', '=', target_customer['id']], ['state', 'in', ['sale', 'done']]]],
        {'fields': ['id', 'name', 'amount_total', 'amount_tax', 'order_line'], 'order': 'id desc', 'limit': 1})
    
    if orders:
        results['order_found'] = True
        order = orders[0]
        results['details']['order_name'] = order['name']
        results['details']['amount_tax'] = order['amount_tax']
        
        # Check Tax
        if float(order['amount_tax']) < 0.01:
            results['order_tax_zero'] = True
            
        # Check Products
        line_ids = order['order_line']
        lines = execute('sale.order.line', 'read',
            [line_ids],
            {'fields': ['product_id', 'product_uom_qty']})
        
        # Verify specific products and quantities
        # Expected: Compost Bin (10), Garden Light (5)
        p1_found = False
        p2_found = False
        
        setup_products = {p['name']: p['id'] for p in setup.get('products', [])}
        
        for l in lines:
            p_name = l['product_id'][1]
            qty = l['product_uom_qty']
            
            if "Compost Bin" in p_name and qty == 10:
                p1_found = True
            if "Garden Light" in p_name and qty == 5:
                p2_found = True
        
        if p1_found and p2_found:
            results['order_products_correct'] = True

# Write full results
with open('/tmp/fiscal_position_result.json', 'w') as f:
    json.dump(results, f, indent=2)

print("Export complete.")
PYEOF

# Move result to allow safe reading
cp /tmp/fiscal_position_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="