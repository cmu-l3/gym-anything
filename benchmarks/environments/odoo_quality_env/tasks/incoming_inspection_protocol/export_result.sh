#!/bin/bash
echo "=== Exporting incoming_inspection_protocol results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/incoming_inspection_protocol_end.png

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, time, re

url = 'http://localhost:8069'
db = 'odoo_quality'
user = 'admin'
pwd = 'admin'

uid = None
for attempt in range(10):
    try:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, user, pwd, {})
        if uid:
            break
    except Exception:
        pass
    time.sleep(3)

if not uid:
    with open('/tmp/incoming_inspection_protocol_result.json', 'w') as f:
        json.dump({}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def sr(model, domain, fields, limit=100):
    try:
        return models.execute_kw(db, uid, pwd, model, 'search_read', [domain], {'fields': fields, 'limit': limit})
    except Exception:
        return []

def strip_html(html_str):
    if not html_str:
        return ''
    return re.sub(r'<[^>]+>', '', str(html_str)).strip()

result = {}

# Check QCP 1: Structural Integrity
qcp1_list = sr('quality.point', [['name', 'ilike', 'Structural Integrity']],
               ['id', 'name', 'product_ids', 'picking_type_ids', 'test_type', 'note', 'failure_message'])
if qcp1_list:
    q = qcp1_list[0]
    result['qcp1_found'] = True
    result['qcp1_test_type'] = q.get('test_type', '')
    result['qcp1_note'] = strip_html(q.get('note', ''))
    result['qcp1_product_ids'] = q.get('product_ids', [])
else:
    result['qcp1_found'] = False

# Check QCP 2: Acoustic Attenuation
qcp2_list = sr('quality.point', [['name', 'ilike', 'Acoustic Attenuation']],
               ['id', 'name', 'product_ids', 'picking_type_ids', 'test_type', 'note'])
if qcp2_list:
    q = qcp2_list[0]
    result['qcp2_found'] = True
    result['qcp2_test_type'] = q.get('test_type', '')
    result['qcp2_note'] = strip_html(q.get('note', ''))
    result['qcp2_product_ids'] = q.get('product_ids', [])
else:
    result['qcp2_found'] = False

# Check QCP 3: Ergonomic Compliance
qcp3_list = sr('quality.point', [['name', 'ilike', 'Ergonomic Compliance']],
               ['id', 'name', 'product_ids', 'picking_type_ids', 'test_type', 'note', 'failure_message'])
if qcp3_list:
    q = qcp3_list[0]
    result['qcp3_found'] = True
    result['qcp3_test_type'] = q.get('test_type', '')
    result['qcp3_failure_message'] = strip_html(q.get('failure_message', ''))
    result['qcp3_product_ids'] = q.get('product_ids', [])
else:
    result['qcp3_found'] = False

# Resolve product IDs to names for checking
for key in ['qcp1_product_ids', 'qcp2_product_ids', 'qcp3_product_ids']:
    pids = result.get(key, [])
    if pids:
        prods = sr('product.product', [['id', 'in', pids]], ['id', 'name'])
        result[key + '_names'] = [p.get('name', '') for p in prods]
    else:
        result[key + '_names'] = []

# Check quality check states
for check_name, key in [
    ('Visual Inspection - Cabinet Finish', 'check_cabinet'),
    ('Dimension Verification - Screen Width', 'check_screen'),
]:
    checks = sr('quality.check', [['name', '=', check_name]], ['id', 'quality_state'])
    if checks:
        result[f'{key}_state'] = checks[0].get('quality_state', '')
    else:
        result[f'{key}_state'] = ''

with open('/tmp/incoming_inspection_protocol_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export result: {json.dumps(result, indent=2)}")
PYTHON_EOF

echo "=== incoming_inspection_protocol export complete ==="
