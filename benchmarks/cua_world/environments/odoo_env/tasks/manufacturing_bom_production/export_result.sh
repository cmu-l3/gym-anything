#!/bin/bash
# Export script for manufacturing_bom_production
# Exports the Bill of Materials and Manufacturing Order status

echo "=== Exporting manufacturing results ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python export
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
    with open('/tmp/manufacturing_setup.json') as f:
        setup = json.load(f)
except Exception:
    setup = {}

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Find Bill of Materials for the product
product_tmpl_id = setup.get('finished_product_id')
bom_data = None
bom_lines_data = []

if product_tmpl_id:
    # Search for BoM linked to this product template
    boms = execute('mrp.bom', 'search_read', 
        [[['product_tmpl_id', '=', product_tmpl_id]]], 
        {'fields': ['id', 'code', 'product_qty', 'type']})
    
    if boms:
        # Take the most recently created one
        bom = boms[-1]
        bom_data = bom
        
        # Get BoM Lines
        lines = execute('mrp.bom.line', 'search_read',
            [[['bom_id', '=', bom['id']]]],
            {'fields': ['product_id', 'product_qty']})
            
        for line in lines:
            # Resolve product name
            pid = line['product_id'][0]
            pname = line['product_id'][1]
            bom_lines_data.append({
                'product_id': pid,
                'product_name': pname,
                'qty': line['product_qty']
            })

# 2. Find Manufacturing Orders for the product
mo_data = None
if product_tmpl_id:
    # We need to find the product.product ID corresponding to the template for the MO search
    variants = execute('product.product', 'search_read', 
        [[['product_tmpl_id', '=', product_tmpl_id]]], 
        {'fields': ['id']})
    
    if variants:
        variant_id = variants[0]['id']
        
        mos = execute('mrp.production', 'search_read',
            [[['product_id', '=', variant_id]]],
            {'fields': ['id', 'name', 'state', 'product_qty', 'date_start', 'bom_id']})
            
        if mos:
            # Get the most recent MO
            mo_data = mos[-1]

# 3. Export Data
result = {
    "bom_found": bool(bom_data),
    "bom_id": bom_data['id'] if bom_data else None,
    "bom_lines": bom_lines_data,
    "mo_found": bool(mo_data),
    "mo_data": mo_data,
    "setup_components": setup.get('component_ids', {}),
    "setup_expected": setup.get('expected_components', [])
}

# Save to temp file
with open('/tmp/manufacturing_bom_production_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export successful")
PYEOF

# Move result to safe location
cp /tmp/manufacturing_bom_production_result.json /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="