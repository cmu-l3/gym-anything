#!/bin/bash
# Export script for loyalty_promotion_setup task
# Verifies the configuration of the loyalty program and the sales order.

echo "=== Exporting loyalty_promotion_setup result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python verification via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

# Load setup data
try:
    with open('/tmp/loyalty_setup.json', 'r') as f:
        setup = json.load(f)
except FileNotFoundError:
    print("Error: Setup file not found")
    setup = {}

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"Error connecting to Odoo: {e}")
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

result = {
    'setup': setup,
    'program_found': False,
    'program_correct': {},
    'rules_correct': {},
    'rewards_correct': {},
    'order_found': False,
    'order_correct': {}
}

# 1. Check if Loyalty Program exists
target_name = setup.get('target_program_name', 'Privacy Screen Bulk Saver')
target_code = setup.get('target_code', 'SCREEN15')

# Search for program by name or code
programs = execute('loyalty.program', 'search_read',
    ['|', ['name', 'ilike', target_name], ['rule_ids.code', '=', target_code]],
    {'fields': ['id', 'name', 'program_type', 'trigger', 'rule_ids', 'reward_ids']})

if programs:
    prog = programs[0] # Take the most relevant one
    result['program_found'] = True
    result['program_correct'] = {
        'name_match': target_name.lower() in prog['name'].lower(),
        'type': prog.get('program_type'), # Expected 'promotion' or 'coupon' depending on version
        'trigger': prog.get('trigger') # 'code' is expected output for Odoo 16/17 logic usually
    }

    # 2. Check Rules (Conditions)
    # Need to fetch the rule objects
    rule_ids = prog.get('rule_ids', [])
    if rule_ids:
        rules = execute('loyalty.rule', 'read', [rule_ids], {'fields': ['minimum_qty', 'product_ids', 'code', 'mode']})
        # Check if any rule matches requirements
        valid_rule = False
        for r in rules:
            # Check for code if it's stored on rule level in this version
            code_match = r.get('code') == target_code
            # Check min qty
            qty_match = r.get('minimum_qty') == 5
            # Check product restriction
            prod_ids = r.get('product_ids', [])
            prod_match = setup.get('product_id') in prod_ids
            
            result['rules_correct'] = {
                'min_qty': r.get('minimum_qty'),
                'product_restricted': bool(prod_ids),
                'correct_product': prod_match,
                'code': r.get('code')
            }
            
            if qty_match and prod_match:
                valid_rule = True
                break
            
            # If code is on the program (trigger='code'), the rule might just define the code
            # In Odoo 16+, Promo Code programs often have the code in the rule
            if code_match and qty_match:
                 valid_rule = True

    # 3. Check Rewards
    reward_ids = prog.get('reward_ids', [])
    if reward_ids:
        rewards = execute('loyalty.reward', 'read', [reward_ids], 
            {'fields': ['discount', 'discount_mode', 'discount_applicability', 'discount_product_ids']})
        
        for r in rewards:
            result['rewards_correct'] = {
                'discount': r.get('discount'),
                'mode': r.get('discount_mode'), # 'percent'
                'applicability': r.get('discount_applicability') # 'specific'
            }

# 4. Check Sales Order
partner_id = setup.get('partner_id')
if partner_id:
    orders = execute('sale.order', 'search_read',
        [[['partner_id', '=', partner_id]]],
        {'fields': ['id', 'name', 'amount_total', 'order_line'], 'order': 'id desc', 'limit': 1})
    
    if orders:
        order = orders[0]
        result['order_found'] = True
        
        # Check lines for discount
        lines = execute('sale.order.line', 'read', [order['order_line']], 
            {'fields': ['product_id', 'product_uom_qty', 'price_unit', 'discount', 'name']})
        
        target_product_id = setup.get('product_id')
        discount_applied = False
        target_qty_found = False
        
        for line in lines:
            pid = line.get('product_id')[0] if isinstance(line.get('product_id'), list) else line.get('product_id')
            qty = line.get('product_uom_qty', 0)
            
            if pid == target_product_id:
                if qty >= 5: # Task asked for 6
                    target_qty_found = True
                
                # Check for direct discount percentage on line
                if line.get('discount') == 15:
                    discount_applied = True
            
            # Check for separate discount line (sometimes rewards are added as separate lines)
            if 'discount' in line.get('name', '').lower() and '15%' in line.get('name', ''):
                discount_applied = True
                
        result['order_correct'] = {
            'target_product_found': target_qty_found,
            'discount_applied': discount_applied
        }

# Save result
with open('/tmp/loyalty_promotion_setup_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/loyalty_promotion_setup_result.json 2>/dev/null || true

echo "Result saved to /tmp/loyalty_promotion_setup_result.json"
cat /tmp/loyalty_promotion_setup_result.json
echo "=== Export complete ==="