#!/bin/bash
# Post-task script for shift_production_material_staging task

source /workspace/scripts/task_utils.sh

# Record screenshot
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

echo "Exporting Odoo state via Python XML-RPC..."
python3 << PYEOF
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    result = {
        'locations': {},
        'move_lines': [],
        'purchase_orders': []
    }

    # 1. Locations
    extruder_loc = execute('stock.location', 'search_read', [[['name', '=', 'Extruder Line 3']]], ['id'], limit=1)
    overflow_loc = execute('stock.location', 'search_read', [[['name', '=', 'Overflow']]], ['id'], limit=1)
    
    result['locations']['extruder_loc_id'] = extruder_loc[0]['id'] if extruder_loc else None
    result['locations']['overflow_loc_id'] = overflow_loc[0]['id'] if overflow_loc else None

    # 2. Product map
    products = execute('product.product', 'search_read', [], ['id', 'default_code'])
    prod_map = {p['id']: p['default_code'] for p in products if p['default_code']}

    # 3. Move lines (Targeting Extruder Line 3)
    # We only care about move lines relevant to the task to prevent huge payloads
    if result['locations']['extruder_loc_id']:
        ext_id = result['locations']['extruder_loc_id']
        move_lines = execute('stock.move.line', 'search_read', [[['location_dest_id', '=', ext_id]]], 
                             ['product_id', 'state', 'qty_done', 'quantity', 'location_id', 'location_dest_id'])
        for ml in move_lines:
            prod_id = ml['product_id'][0] if ml.get('product_id') else None
            if not prod_id or prod_id not in prod_map: continue
            
            result['move_lines'].append({
                'product_code': prod_map[prod_id],
                'state': ml.get('state', ''),
                'qty_done': ml.get('qty_done', ml.get('quantity', 0)),
                'quantity': ml.get('quantity', ml.get('qty_done', 0)),
                'source_loc_id': ml['location_id'][0] if ml.get('location_id') else None,
                'dest_loc_id': ml['location_dest_id'][0] if ml.get('location_dest_id') else None
            })

    # 4. Purchase Orders
    pos = execute('purchase.order', 'search_read', [], ['id', 'state', 'partner_id'])
    for po in pos:
        partner_name = po['partner_id'][1] if po.get('partner_id') else ''
        po_lines = execute('purchase.order.line', 'search_read', [[['order_id', '=', po['id']]]], ['product_id', 'product_qty'])
        
        lines_data = []
        for line in po_lines:
            prod_id = line['product_id'][0] if line.get('product_id') else None
            if prod_id and prod_id in prod_map:
                lines_data.append({
                    'product_code': prod_map[prod_id],
                    'qty': line.get('product_qty', 0)
                })
        
        result['purchase_orders'].append({
            'state': po.get('state', ''),
            'vendor_name': partner_name,
            'lines': lines_data
        })

    with open('/tmp/staging_result.json', 'w') as f:
        json.dump(result, f, indent=2)

    print("State successfully exported to /tmp/staging_result.json")

except Exception as e:
    print(f"Error during export: {e}")
    with open('/tmp/staging_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)
PYEOF

echo "=== Export Complete ==="