#!/bin/bash
# Export script for lot_tracking_expiry_receipt
# Exports final state of products, lots, and picking

echo "=== Exporting lot_tracking_expiry_receipt Result ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ ! -f /tmp/lot_tracking_setup.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/task_result.json
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
with open('/tmp/lot_tracking_setup.json') as f:
    setup = json.load(f)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f"Connection failed: {e}"}
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, *args, **kwargs):
    return models.execute_kw(DB, uid, PASSWORD, model, method, list(args), kwargs or {})

# 1. Check Product Configuration
products = execute('product.product', 'read', [setup['prod1_id'], setup['prod2_id']], ['tracking'])
prod1_tracking = next((p['tracking'] for p in products if p['id'] == setup['prod1_id']), 'none')
prod2_tracking = next((p['tracking'] for p in products if p['id'] == setup['prod2_id']), 'none')

# 2. Check Lots
# Search for lots by expected name
lot1_recs = execute('stock.lot', 'search_read', 
    [['name', '=', setup['prod1_expected_lot']], ['product_id', '=', setup['prod1_id']]], 
    ['name', 'expiration_date', 'product_qty'])

lot2_recs = execute('stock.lot', 'search_read', 
    [['name', '=', setup['prod2_expected_lot']], ['product_id', '=', setup['prod2_id']]], 
    ['name', 'expiration_date', 'product_qty'])

lot1 = lot1_recs[0] if lot1_recs else None
lot2 = lot2_recs[0] if lot2_recs else None

# 3. Check Picking State
picking = execute('stock.picking', 'read', [setup['picking_id']], ['state'])[0]
picking_state = picking['state']

# Prepare Result
result = {
    'prod1_tracking': prod1_tracking,
    'prod2_tracking': prod2_tracking,
    'lot1_exists': bool(lot1),
    'lot2_exists': bool(lot2),
    'lot1_expiry': lot1.get('expiration_date') if lot1 else None,
    'lot2_expiry': lot2.get('expiration_date') if lot2 else None,
    'lot1_qty': lot1.get('product_qty', 0) if lot1 else 0,
    'lot2_qty': lot2.get('product_qty', 0) if lot2 else 0,
    'picking_state': picking_state,
    'expected': {
        'prod1_lot': setup['prod1_expected_lot'],
        'prod2_lot': setup['prod2_expected_lot'],
        'prod1_expiry': setup['prod1_expected_expiry'],
        'prod2_expiry': setup['prod2_expected_expiry']
    },
    'timestamp': os.popen('date +%s').read().strip()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export completed.")
PYEOF

chmod 666 /tmp/task_result.json
cat /tmp/task_result.json
echo "=== Export Complete ==="