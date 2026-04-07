#!/bin/bash
# Export script for bar_inventory_uom_conversion task

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png ga || true

cat << 'PYEOF' > /tmp/export_bar.py
import xmlrpc.client
import json
import os

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
uid = common.authenticate(db, 'admin', password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

result = {
    'task_start': int(os.environ.get('TASK_START', '0')),
    'uoms': [],
    'purchase_orders': [],
    'stock': {},
    'uom_enabled': False
}

try:
    # Gather UoMs
    uoms = execute('uom.uom', 'search_read', [], ['name', 'category_id', 'uom_type', 'factor', 'factor_inv', 'ratio'])
    result['uoms'] = uoms
    
    # Gather PO and Lines
    pos = execute('purchase.order', 'search_read', [[('partner_id.name', 'ilike', "Southern Glazer")]], ['name', 'state', 'order_line'])
    po_data = []
    for po in pos:
        lines = execute('purchase.order.line', 'read', po['order_line'], ['product_id', 'product_qty', 'product_uom', 'price_unit'])
        po_data.append({
            'id': po['id'],
            'name': po['name'],
            'state': po['state'],
            'lines': lines
        })
    result['purchase_orders'] = po_data

    # Gather stock
    def get_stock(code):
        prod = execute('product.product', 'search_read', [[('default_code', '=', code)]], ['id'])
        if not prod: return 0
        quants = execute('stock.quant', 'search_read', [[('product_id', '=', prod[0]['id']), ('location_id.usage', '=', 'internal')]], ['quantity'])
        return sum(q['quantity'] for q in quants)

    result['stock']['gin'] = get_stock('BAR-GIN-001')
    result['stock']['bbn'] = get_stock('BAR-BBN-001')

    # Verify UoM feature status
    uom_group = execute('ir.model.data', 'search_read', [[('module', '=', 'uom'), ('name', '=', 'group_uom')]], ['res_id'])
    if uom_group:
        admin_user = execute('res.users', 'read', [2], ['groups_id'])[0]
        result['uom_enabled'] = uom_group[0]['res_id'] in admin_user['groups_id']

except Exception as e:
    result['error'] = str(e)

with open('/tmp/uom_conversion_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

export TASK_START
python3 /tmp/export_bar.py
chmod 666 /tmp/uom_conversion_result.json

echo "Export complete. Result saved to /tmp/uom_conversion_result.json"
cat /tmp/uom_conversion_result.json