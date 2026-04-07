#!/bin/bash
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/job_site_task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/job_site_final.png" || true

python3 << PYEOF
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)
except Exception:
    sys.exit(0)

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

task_start = int(os.environ.get('TASK_START', '0'))

# Get Locations
wh = execute('stock.warehouse', 'search_read', [[]], fields=['lot_stock_id'], limit=1)
wh_stock_id = wh[0]['lot_stock_id'][0] if wh else None

job_site_locs = execute('stock.location', 'search_read', [[['name', '=', 'Job Site - Riverfront']]], fields=['id', 'usage'])
job_site_id = job_site_locs[0]['id'] if job_site_locs else None

# Get Vendor
vendor = execute('res.partner', 'search_read', [[['name', '=', 'BuildMart Wholesale']]], fields=['id'], limit=1)
vendor_id = vendor[0]['id'] if vendor else None

product_codes = ['CONST-BEAM-01', 'CONST-CEM-02', 'CONST-TILE-03', 'CONST-WIRE-04', 'CONST-HAZ-05']

result = {
    'task_start': task_start,
    'location_created': job_site_id is not None,
    'job_site_id': job_site_id,
    'wh_stock_id': wh_stock_id,
    'products': {},
    'purchase_orders': [],
    'direct_receipts': False,
    'internal_transfers': False
}

prod_map = {}
for code in product_codes:
    tmpl = execute('product.template', 'search_read', [[['default_code', '=', code]]], fields=['id', 'name', 'product_variant_id'], limit=1)
    if tmpl:
        pid = tmpl[0]['product_variant_id'][0]
        prod_map[pid] = code
        
        # Get Job Site Stock
        site_qty = 0
        if job_site_id:
            quants = execute('stock.quant', 'search_read', [[['product_id', '=', pid], ['location_id', '=', job_site_id]]], fields=['quantity'])
            site_qty = sum(q['quantity'] for q in quants)
            
        # Get WH Stock
        wh_qty = 0
        if wh_stock_id:
            quants = execute('stock.quant', 'search_read', [[['product_id', '=', pid], ['location_id', '=', wh_stock_id]]], fields=['quantity'])
            wh_qty = sum(q['quantity'] for q in quants)

        result['products'][code] = {
            'job_site_qty': site_qty,
            'wh_stock_qty': wh_qty,
            'po_qty': 0
        }

# Process POs
pos = execute('purchase.order', 'search_read', [[['partner_id', '=', vendor_id], ['state', 'in', ['purchase', 'done']]]], fields=['id', 'name', 'picking_ids'])
for po in pos:
    po_data = {'name': po['name'], 'lines': [], 'direct_receipt': False}
    
    # Check lines
    lines = execute('purchase.order.line', 'search_read', [[['order_id', '=', po['id']]]], fields=['product_id', 'product_qty'])
    for line in lines:
        pid = line['product_id'][0]
        if pid in prod_map:
            code = prod_map[pid]
            result['products'][code]['po_qty'] += line['product_qty']
            po_data['lines'].append({'code': code, 'qty': line['product_qty']})
            
    # Check if receipt went directly to Job Site
    if po['picking_ids']:
        pickings = execute('stock.picking', 'search_read', [[['id', 'in', po['picking_ids']], ['state', '=', 'done']]], fields=['location_dest_id'])
        for pick in pickings:
            if job_site_id and pick['location_dest_id'][0] == job_site_id:
                po_data['direct_receipt'] = True
                result['direct_receipts'] = True
                
    result['purchase_orders'].append(po_data)

# Process Internal Transfers
if job_site_id and wh_stock_id:
    internal_picks = execute('stock.picking', 'search_read', [[['location_id', '=', wh_stock_id], ['location_dest_id', '=', job_site_id], ['state', '=', 'done']]], fields=['id'])
    if internal_picks:
        result['internal_transfers'] = True

with open('/tmp/job_site_staging_result.json', 'w') as f:
    json.dump(result, f, indent=2)
os.chmod('/tmp/job_site_staging_result.json', 0o666)

print("Result JSON saved.")
PYEOF