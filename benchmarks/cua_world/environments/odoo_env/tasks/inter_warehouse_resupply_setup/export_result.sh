#!/bin/bash
# Export script for inter_warehouse_resupply_setup

echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Export results via Python XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    # Fail gracefully with error json
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Data collection
result = {
    "warehouse_created": False,
    "resupply_route_configured": False,
    "reordering_rule_correct": False,
    "transfer_created": False,
    "transfer_validated": False,
    "stock_correct": False,
    "pop_warehouse_code": None,
    "details": {}
}

# 1. Check Warehouse 'Downtown Pop-up' (POP)
target_code = 'POP'
warehouses = execute('stock.warehouse', 'search_read', 
    [[['code', '=', target_code]]], 
    {'fields': ['id', 'name', 'code', 'resupply_wh_ids', 'lot_stock_id']})

if warehouses:
    wh = warehouses[0]
    result["warehouse_created"] = True
    result["pop_warehouse_code"] = wh['code']
    pop_location_id = wh['lot_stock_id'][0]
    
    # 2. Check Resupply Configuration
    # resupply_wh_ids should contain the ID of the San Francisco warehouse
    # Find SF warehouse first
    sf_warehouses = execute('stock.warehouse', 'search_read', 
        [[['code', 'in', ['WH', 'SF']]]], {'fields': ['id', 'code']})
    
    if sf_warehouses:
        sf_id = sf_warehouses[0]['id']
        if sf_id in wh['resupply_wh_ids']:
            result["resupply_route_configured"] = True
    
    # 3. Check Reordering Rule
    # Search for rules at POP location for 'Acoustic Bloc Screen'
    products = execute('product.product', 'search_read', [[['name', '=', 'Acoustic Bloc Screen']]], {'fields': ['id']})
    if products:
        pid = products[0]['id']
        rules = execute('stock.warehouse.orderpoint', 'search_read', 
            [[['location_id', '=', pop_location_id], ['product_id', '=', pid]]], 
            {'fields': ['product_min_qty', 'product_max_qty']})
        
        if rules:
            rule = rules[0]
            if abs(rule['product_min_qty'] - 10.0) < 0.1 and abs(rule['product_max_qty'] - 30.0) < 0.1:
                result["reordering_rule_correct"] = True
            result["details"]["rule"] = rule

        # 4. Check Stock Transfer
        # Look for pickings Dest Location = POP Location, Source Location inside SF
        # We need the SF Stock location ID
        sf_stock_loc = execute('stock.warehouse', 'read', [sf_id], {'fields': ['lot_stock_id']})[0]['lot_stock_id'][0]
        
        # Search for internal transfers
        transfers = execute('stock.picking', 'search_read', 
            [[['location_dest_id', '=', pop_location_id], 
              ['location_id', 'child_of', sf_id], # Actually location_id should be source warehouse view loc or stock loc
              ['product_id', '=', pid]]],
            {'fields': ['state', 'location_id', 'location_dest_id']})
        
        # Broaden search: Just check if *any* incoming transfer to POP for this product exists
        if not transfers:
             transfers = execute('stock.picking', 'search_read', 
            [[['location_dest_id', '=', pop_location_id], 
              ['product_id', '=', pid]]],
            {'fields': ['state', 'location_id', 'location_dest_id']})

        if transfers:
            result["transfer_created"] = True
            # Check if any is done
            if any(t['state'] == 'done' for t in transfers):
                result["transfer_validated"] = True
        
        # 5. Check Final Stock at POP
        quants = execute('stock.quant', 'search_read',
            [[['location_id', '=', pop_location_id], ['product_id', '=', pid]]],
            {'fields': ['quantity']})
        
        qty = sum(q['quantity'] for q in quants)
        if qty >= 10:
            result["stock_correct"] = True
        result["details"]["final_qty"] = qty

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

PYEOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json