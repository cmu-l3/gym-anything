#!/bin/bash
# Export script for manufacturing_variant_bom_setup
# Verifies the BoM configuration and the test Manufacturing Order

echo "=== Exporting task results ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python verification
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
if not os.path.exists('/tmp/bom_setup.json'):
    print("ERROR: Setup data missing")
    sys.exit(0)

with open('/tmp/bom_setup.json') as f:
    setup = json.load(f)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Connection failed: {e}")
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

template_id = setup['template_id']
ptavs = setup['ptavs'] # Mapping Name -> ID
comps = setup['components'] # Mapping Name -> ID

results = {
    "bom_exists": False,
    "bom_lines_count": 0,
    "logic_correct": {
        "frame": False,
        "hardware": False,
        "motor_std": False,
        "motor_pro": False,
        "top_oak": False,
        "top_white": False,
        "cable_tray": False
    },
    "mo_created": False,
    "mo_components_correct": False,
    "mo_components_found": []
}

# 1. Verify BoM Configuration
boms = execute('mrp.bom', 'search_read', 
    [[['product_tmpl_id', '=', template_id]]], 
    {'fields': ['id', 'bom_line_ids']})

if boms:
    results['bom_exists'] = True
    bom = boms[0]
    
    # Get lines
    lines = execute('mrp.bom.line', 'read', bom['bom_line_ids'], 
        ['product_id', 'bom_product_template_attribute_value_ids'])
    
    results['bom_lines_count'] = len(lines)
    
    for line in lines:
        prod_id = line['product_id'][0]
        prod_name = line['product_id'][1]
        attr_ids = line['bom_product_template_attribute_value_ids'] # List of IDs
        
        # Helper to check logic
        def check_logic(comp_key, expected_ptav_names):
            if comps[comp_key] == prod_id:
                expected_ids = [ptavs[n] for n in expected_ptav_names]
                # Check if sets match (ignoring order)
                if set(attr_ids) == set(expected_ids):
                    results['logic_correct'][comp_key.lower().replace(" ", "_")] = True
                    # Mapping specific keys to setup keys
                    if comp_key == "Desk Frame (Universal)": results['logic_correct']['frame'] = True
                    if comp_key == "Assembly Hardware Kit": results['logic_correct']['hardware'] = True
                    if comp_key == "Standard Motor Unit": results['logic_correct']['motor_std'] = True
                    if comp_key == "Pro Heavy-Duty Motor Unit": results['logic_correct']['motor_pro'] = True
                    if comp_key == "Oak Desktop Board": results['logic_correct']['top_oak'] = True
                    if comp_key == "White Desktop Board": results['logic_correct']['top_white'] = True
                    if comp_key == "Cable Management Tray": results['logic_correct']['cable_tray'] = True

        # Frame & Hardware: Should have NO attribute restrictions (empty list)
        if prod_id == comps["Desk Frame (Universal)"]:
            if not attr_ids: results['logic_correct']['frame'] = True
        if prod_id == comps["Assembly Hardware Kit"]:
            if not attr_ids: results['logic_correct']['hardware'] = True
            
        # Motors
        if prod_id == comps["Standard Motor Unit"]:
            if set(attr_ids) == {ptavs["Standard"]}: results['logic_correct']['motor_std'] = True
        if prod_id == comps["Pro Heavy-Duty Motor Unit"]:
            if set(attr_ids) == {ptavs["Pro"]}: results['logic_correct']['motor_pro'] = True
            
        # Tops
        if prod_id == comps["Oak Desktop Board"]:
            if set(attr_ids) == {ptavs["Oak"]}: results['logic_correct']['top_oak'] = True
        if prod_id == comps["White Desktop Board"]:
            if set(attr_ids) == {ptavs["White"]}: results['logic_correct']['top_white'] = True
            
        # Accessory
        if prod_id == comps["Cable Management Tray"]:
            if set(attr_ids) == {ptavs["Pro"]}: results['logic_correct']['cable_tray'] = True


# 2. Verify Manufacturing Order (MO) for "Pro, White"
# We need to find the specific variant ID for Pro + White
# Find product.product where product_tmpl_id = template_id and has appropriate values
# This is tricky via search domain on variants, simpler to search via name if generated correctly or attribute_value_ids
# Let's search all variants of the template
variants = execute('product.product', 'search_read', 
    [[['product_tmpl_id', '=', template_id]]], 
    {'fields': ['id', 'product_template_attribute_value_ids']})

target_variant_id = None
pro_id = ptavs['Pro']
white_id = ptavs['White']

for v in variants:
    v_ptavs = v['product_template_attribute_value_ids']
    if pro_id in v_ptavs and white_id in v_ptavs:
        target_variant_id = v['id']
        break

if target_variant_id:
    # Find MOs for this variant created recently
    mos = execute('mrp.production', 'search_read',
        [[['product_id', '=', target_variant_id]]],
        {'fields': ['move_raw_ids', 'state'], 'order': 'id desc', 'limit': 1})
        
    if mos:
        results['mo_created'] = True
        mo = mos[0]
        # Check components (stock moves)
        moves = execute('stock.move', 'read', mo['move_raw_ids'], ['product_id'])
        
        move_prod_ids = [m['product_id'][0] for m in moves]
        results['mo_components_found'] = [m['product_id'][1] for m in moves]
        
        # Expected components for Pro + White:
        expected = {
            comps["Desk Frame (Universal)"],
            comps["Assembly Hardware Kit"],
            comps["Pro Heavy-Duty Motor Unit"],
            comps["White Desktop Board"],
            comps["Cable Management Tray"]
        }
        
        # Forbidden components
        forbidden = {
            comps["Standard Motor Unit"],
            comps["Oak Desktop Board"]
        }
        
        found_set = set(move_prod_ids)
        
        if expected.issubset(found_set) and found_set.isdisjoint(forbidden):
            results['mo_components_correct'] = True

# Export results
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)

print("Export complete.")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true