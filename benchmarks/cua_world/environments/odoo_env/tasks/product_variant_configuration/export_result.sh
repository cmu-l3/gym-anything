#!/bin/bash
# Export script for product_variant_configuration
# Queries Odoo to verify the created product, its attributes, and variants

echo "=== Exporting product_variant_configuration results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Run Python extraction script
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'
PRODUCT_NAME = 'Alpine Performance Jacket'

result = {
    'product_found': False,
    'attributes_found': {},
    'variants_count': 0,
    'price_extras_found': {},
    'task_start': 0,
    'create_date': None
}

# Load task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['task_start'] = float(f.read().strip())
except:
    pass

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

    # 1. Search for the product template
    # We search by name. If multiple, we take the most recent one.
    product_ids = models.execute_kw(DB, uid, PASSWORD, 'product.template', 'search', 
        [[['name', '=', PRODUCT_NAME]]], {'limit': 1, 'order': 'id desc'})

    if product_ids:
        pid = product_ids[0]
        product = models.execute_kw(DB, uid, PASSWORD, 'product.template', 'read', 
            [[pid]], {'fields': ['name', 'list_price', 'standard_price', 'type', 'default_code', 'description_sale', 'create_date', 'attribute_line_ids']})[0]

        result['product_found'] = True
        result['product_data'] = product
        result['create_date'] = product.get('create_date')

        # 2. Check Attributes (via attribute lines)
        line_ids = product.get('attribute_line_ids', [])
        if line_ids:
            # Read the lines
            lines = models.execute_kw(DB, uid, PASSWORD, 'product.template.attribute.line', 'read',
                [line_ids], {'fields': ['attribute_id', 'value_ids', 'product_template_value_ids']})
            
            for line in lines:
                # Get attribute name
                attr_id = line['attribute_id'][0]
                attr_name = line['attribute_id'][1]
                
                # Get value names
                value_ids = line['value_ids']
                values = models.execute_kw(DB, uid, PASSWORD, 'product.attribute.value', 'read',
                    [value_ids], {'fields': ['name']})
                value_names = [v['name'] for v in values]
                
                result['attributes_found'][attr_name] = value_names

                # 3. Check Price Extras
                # Price extras are stored on 'product.template.attribute.value'
                # which links a template line to a value and stores the extra price
                ptv_ids = line.get('product_template_value_ids', [])
                if ptv_ids:
                    ptvs = models.execute_kw(DB, uid, PASSWORD, 'product.template.attribute.value', 'read',
                        [ptv_ids], {'fields': ['name', 'price_extra', 'product_attribute_value_id']})
                    
                    for ptv in ptvs:
                        # ptv['name'] usually looks like "Size: XL" or just "XL" depending on version
                        # safer to look up the attribute value name if needed, but 'name' field usually suffices
                        val_name = ptv['name']
                        extra = ptv['price_extra']
                        if extra != 0.0:
                            # Clean the name if it comes as "Size: XL" -> "XL"
                            clean_name = val_name.split(': ')[-1] if ': ' in val_name else val_name
                            result['price_extras_found'][clean_name] = extra

        # 4. Count Variants
        variant_count = models.execute_kw(DB, uid, PASSWORD, 'product.product', 'search_count',
            [[['product_tmpl_id', '=', pid]]])
        result['variants_count'] = variant_count

except Exception as e:
    result['error'] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Move result to allow copy_from_env
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="