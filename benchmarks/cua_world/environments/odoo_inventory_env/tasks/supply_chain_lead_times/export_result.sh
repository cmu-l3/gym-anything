#!/bin/bash
# Export script for Supply Chain Lead Times Task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="
take_screenshot "/tmp/task_final_state.png" || true
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

python3 << 'PYEOF'
import xmlrpc.client
import json
import os

url = 'http://localhost:8069'
db = 'odoo_inventory'
user = 'admin'
password = 'admin'

result = {
    'task_start': int(os.environ.get('TASK_START', '0')),
    'products': {}
}

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url), allow_none=True)
    uid = common.authenticate(db, user, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url), allow_none=True)

    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    # 1. Get Company Security Lead Times
    company = execute('res.company', 'search_read', [[]], fields=['security_lead', 'po_lead'], limit=1)[0]
    result['security_lead'] = company.get('security_lead', 0.0)
    result['po_lead'] = company.get('po_lead', 0.0)

    # 2. Get Vendor ID
    vendor = execute('res.partner', 'search_read', [[('name', '=', 'GlobalTech Industries')]], fields=['id'], limit=1)
    vendor_id = vendor[0]['id'] if vendor else None
    result['vendor_id'] = vendor_id

    # 3. Get Product Lead Times
    codes = ['COMP-MCU-STM32', 'COMP-WIFI-ESP32', 'COMP-SBC-RPI4']
    for code in codes:
        tmpl = execute('product.template', 'search_read', [[('default_code', '=', code)]], fields=['id', 'name', 'sale_delay'], limit=1)
        if tmpl:
            t = tmpl[0]
            # Check vendor supplier info
            supplier_info = execute('product.supplierinfo', 'search_read',
                [[('product_tmpl_id', '=', t['id']), ('partner_id', '=', vendor_id)]],
                fields=['delay'])
            
            vendor_delay = supplier_info[0]['delay'] if supplier_info else 0.0
            
            result['products'][code] = {
                'found': True,
                'sale_delay': t['sale_delay'],
                'has_vendor': bool(supplier_info),
                'vendor_delay': vendor_delay
            }
        else:
            result['products'][code] = {'found': False}
            
except Exception as e:
    result['error'] = str(e)

# Write to tmp file
with open('/tmp/supply_chain_lead_times_result.json', 'w') as f:
    json.dump(result, f, indent=2)

os.chmod('/tmp/supply_chain_lead_times_result.json', 0o666)
PYEOF

echo "Result JSON saved to /tmp/supply_chain_lead_times_result.json"
cat /tmp/supply_chain_lead_times_result.json
echo "=== Export Complete ==="