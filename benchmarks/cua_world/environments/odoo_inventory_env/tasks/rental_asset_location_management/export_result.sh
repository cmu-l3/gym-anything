#!/bin/bash
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/rental_asset_task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/rental_asset_final.png" || true

python3 << PYEOF
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    if not uid:
        raise Exception("Authentication failed")
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    # 1. Find the 3 specific locations
    loc_stock = execute('stock.location', 'search_read', [[['name', '=', 'Stock'], ['usage', '=', 'internal']]], fields=['id'])[0]['id']
    loc_rent = execute('stock.location', 'search_read', [[['name', '=', 'Out on Rent'], ['usage', '=', 'internal']]], fields=['id'])[0]['id']
    loc_maint = execute('stock.location', 'search_read', [[['name', '=', 'Maintenance'], ['usage', '=', 'internal']]], fields=['id'])[0]['id']

    def get_loc_name(loc_id):
        if loc_id == loc_stock: return "WH/Stock"
        if loc_id == loc_rent: return "WH/Out on Rent"
        if loc_id == loc_maint: return "WH/Maintenance"
        return "Other"

    result = {
        "task_start": int(os.environ.get('TASK_START', '0')),
        "red_komodo_locations": {},
        "vmount_battery_rent": 0,
        "mixer_locations": {},
        "boom_mic_stock": 0,
        "boom_mic_maint": 0,
        "sony_venice_locations": {}
    }

    # RED Komodos
    red_prod = execute('product.product', 'search', [[['name', '=', 'RED Komodo 6K Camera']]])[0]
    red_quants = execute('stock.quant', 'search_read', [[['product_id', '=', red_prod]]], fields=['lot_id', 'location_id', 'quantity'])
    for q in red_quants:
        if q['quantity'] > 0 and q['lot_id']:
            result['red_komodo_locations'][q['lot_id'][1]] = get_loc_name(q['location_id'][0])

    # V-Mount Battery
    batt_prod = execute('product.product', 'search', [[['name', '=', 'V-Mount Battery 98Wh']]])[0]
    batt_quants = execute('stock.quant', 'search_read', [[['product_id', '=', batt_prod], ['location_id', '=', loc_rent]]], fields=['quantity'])
    result['vmount_battery_rent'] = sum(q['quantity'] for q in batt_quants)

    # Sound Devices Mixer
    mix_prod = execute('product.product', 'search', [[['name', '=', 'Sound Devices 833 Mixer']]])[0]
    mix_quants = execute('stock.quant', 'search_read', [[['product_id', '=', mix_prod]]], fields=['lot_id', 'location_id', 'quantity'])
    for q in mix_quants:
        if q['quantity'] > 0 and q['lot_id']:
            result['mixer_locations'][q['lot_id'][1]] = get_loc_name(q['location_id'][0])

    # Sennheiser Mics
    mic_prod = execute('product.product', 'search', [[['name', '=', 'Sennheiser MKH416 Boom Mic']]])[0]
    
    mic_stock_quants = execute('stock.quant', 'search_read', [[['product_id', '=', mic_prod], ['location_id', '=', loc_stock]]], fields=['quantity'])
    result['boom_mic_stock'] = sum(q['quantity'] for q in mic_stock_quants)
    
    mic_maint_quants = execute('stock.quant', 'search_read', [[['product_id', '=', mic_prod], ['location_id', '=', loc_maint]]], fields=['quantity'])
    result['boom_mic_maint'] = sum(q['quantity'] for q in mic_maint_quants)

    # Sony Venice
    sony_prod = execute('product.product', 'search', [[['name', '=', 'Sony Venice 2 Camera']]])[0]
    sony_quants = execute('stock.quant', 'search_read', [[['product_id', '=', sony_prod]]], fields=['lot_id', 'location_id', 'quantity'])
    for q in sony_quants:
        if q['quantity'] > 0 and q['lot_id']:
            result['sony_venice_locations'][q['lot_id'][1]] = get_loc_name(q['location_id'][0])

    with open('/tmp/rental_asset_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    os.chmod('/tmp/rental_asset_result.json', 0o666)
    
except Exception as e:
    print(f"Failed to export: {e}")
    # Write empty result on failure to prevent crash
    with open('/tmp/rental_asset_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)
    os.chmod('/tmp/rental_asset_result.json', 0o666)

print("Export complete.")
PYEOF