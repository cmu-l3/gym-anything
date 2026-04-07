#!/bin/bash
# Export script for blanket_purchase_agreement_calloff task

echo "=== Exporting Blanket Agreement Result ==="

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ ! -f /tmp/blanket_order_setup.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/blanket_purchase_agreement_calloff_result.json
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

# Load setup data
try:
    with open('/tmp/blanket_order_setup.json') as f:
        setup = json.load(f)
except Exception as e:
    # Fallback error json
    with open('/tmp/blanket_purchase_agreement_calloff_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
    sys.exit(0)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    with open('/tmp/blanket_purchase_agreement_calloff_result.json', 'w') as f:
        json.dump({'error': f"Connection failed: {e}"}, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

vendor_id = setup['vendor_id']
product_id = setup['product_id']

# 1. Check if 'Purchase Agreements' feature is effectively enabled
# We check if the 'purchase_requisition' module is installed and state is 'installed'
module_status = 'not_installed'
try:
    mods = execute('ir.module.module', 'search_read', 
        [[['name', '=', 'purchase_requisition']]], 
        {'fields': ['state']})
    if mods:
        module_status = mods[0]['state']
except:
    pass

# 2. Find Agreements (Blanket Orders)
# Model is 'purchase.requisition'
# Type 'Blanket Order' usually has ID 2 in demo data, but we search by name 'Blanket Order'
type_id = None
try:
    types = execute('purchase.requisition.type', 'search_read', [[['name', '=', 'Blanket Order']]], {'fields': ['id']})
    if types:
        type_id = types[0]['id']
except:
    pass

agreements = []
try:
    domain = [['vendor_id', '=', vendor_id], ['state', 'in', ['ongoing', 'open', 'done']]] 
    # 'ongoing'/'open' is confirmed state for blanket orders
    
    if type_id:
        domain.append(['type_id', '=', type_id])
        
    agreements_data = execute('purchase.requisition', 'search_read', 
        domain, 
        {'fields': ['id', 'name', 'state', 'line_ids', 'type_id']})
        
    for ag in agreements_data:
        # Check lines for product and price
        lines = execute('purchase.requisition.line', 'read', 
            ag['line_ids'], 
            {'fields': ['product_id', 'product_qty', 'price_unit']})
            
        ag['lines_details'] = lines
        agreements.append(ag)
except Exception as e:
    print(f"Error querying agreements: {e}")

# 3. Find Purchase Orders linked to agreements
orders = []
try:
    # We look for POs created recently for this vendor
    pos = execute('purchase.order', 'search_read',
        [[['partner_id', '=', vendor_id], ['requisition_id', '!=', False]]],
        {'fields': ['id', 'name', 'state', 'requisition_id', 'order_line']})
        
    for po in pos:
        lines = execute('purchase.order.line', 'read', 
            po['order_line'], 
            {'fields': ['product_id', 'product_qty', 'price_unit']})
        po['lines_details'] = lines
        orders.append(po)
except Exception as e:
    print(f"Error querying orders: {e}")

# 4. Construct Result
result = {
    'setup': setup,
    'module_status': module_status,
    'agreements': agreements,
    'orders': orders,
    'timestamp': str(datetime.datetime.now())
}

with open('/tmp/blanket_purchase_agreement_calloff_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF