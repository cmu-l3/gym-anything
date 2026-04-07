#!/bin/bash
# Export script for multicurrency_purchase_order task
# Queries:
# 1. Vendor existence and details
# 2. Purchase Order existence, currency, and state
# 3. Order lines details

echo "=== Exporting multicurrency_purchase_order result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Execute export via Python/XML-RPC
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
    with open('/tmp/multicurrency_po_setup.json') as f:
        setup = json.load(f)
except Exception:
    setup = {}

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    # Fail gracefully if Odoo is down
    print(json.dumps({"error": str(e)}))
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Check Vendor
vendor_name = "Rhine Valley Components GmbH"
vendor = execute('res.partner', 'search_read', 
    [[['name', 'ilike', 'Rhine Valley Components']]], 
    {'fields': ['id', 'name', 'country_id', 'is_company', 'email', 'phone', 'city'], 'limit': 1})

vendor_data = {}
vendor_found = False
vendor_id = None

if vendor:
    v = vendor[0]
    vendor_found = True
    vendor_id = v['id']
    vendor_data = {
        'id': v['id'],
        'name': v['name'],
        'is_company': v['is_company'],
        'country_id': v['country_id'][0] if v['country_id'] else None,
        'country_name': v['country_id'][1] if v['country_id'] else None,
        'city': v['city'],
        'email': v['email'],
        'phone': v['phone']
    }

# 2. Check Purchase Order
po_data = {}
po_found = False

if vendor_found:
    # Find POs for this vendor created recently
    pos = execute('purchase.order', 'search_read',
        [[['partner_id', '=', vendor_id]]],
        {'fields': ['id', 'name', 'state', 'currency_id', 'amount_total', 'order_line'], 'order': 'id desc', 'limit': 1})
    
    if pos:
        po = pos[0]
        po_found = True
        
        # Get lines
        lines_data = []
        if po['order_line']:
            lines = execute('purchase.order.line', 'read',
                [po['order_line']],
                {'fields': ['product_id', 'product_qty', 'price_unit']})
            
            for l in lines:
                lines_data.append({
                    'product_id': l['product_id'][0] if l['product_id'] else None,
                    'product_name': l['product_id'][1] if l['product_id'] else None,
                    'qty': l['product_qty'],
                    'price_unit': l['price_unit']
                })

        po_data = {
            'id': po['id'],
            'state': po['state'],
            'currency_id': po['currency_id'][0] if po['currency_id'] else None,
            'currency_name': po['currency_id'][1] if po['currency_id'] else None,
            'amount_total': po['amount_total'],
            'lines': lines_data
        }

# Result JSON
result = {
    'task_start': int(os.environ.get('TASK_START', 0) or 0),
    'vendor_found': vendor_found,
    'vendor': vendor_data,
    'po_found': po_found,
    'po': po_data,
    'setup_products': setup.get('products', {})
}

with open('/tmp/multicurrency_po_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Safely move result to avoid permission issues
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/multicurrency_po_result.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/multicurrency_po_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="