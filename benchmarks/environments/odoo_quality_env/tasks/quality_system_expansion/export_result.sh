#!/bin/bash
echo "=== Exporting quality_system_expansion results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/quality_system_expansion_end.png

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
    with open('/tmp/quality_system_expansion_result.json', 'w') as f:
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

# 1. Check for team
teams = sr('quality.alert.team', [['name', '=', 'Product Line B - Compliance Unit']], ['id', 'name'])
result['team_found'] = len(teams) > 0

# 2. Check QCP "Surface Finish Verification"
qcp1_list = sr('quality.point', [['name', 'ilike', 'Surface Finish Verification']],
               ['id', 'name', 'product_ids', 'test_type', 'failure_message'])
if qcp1_list:
    q = qcp1_list[0]
    result['qcp1_found'] = True
    result['qcp1_test_type'] = q.get('test_type', '')
    result['qcp1_failure_message'] = strip_html(q.get('failure_message', ''))
    pids = q.get('product_ids', [])
    if pids:
        prods = sr('product.product', [['id', 'in', pids]], ['id', 'name'])
        result['qcp1_product_names'] = [p.get('name', '') for p in prods]
    else:
        result['qcp1_product_names'] = []
else:
    result['qcp1_found'] = False
    result['qcp1_test_type'] = ''
    result['qcp1_failure_message'] = ''
    result['qcp1_product_names'] = []

# 3. Check QCP "Load-Bearing Capacity Test"
qcp2_list = sr('quality.point', [['name', 'ilike', 'Load-Bearing Capacity Test']],
               ['id', 'name', 'product_ids', 'test_type', 'failure_message'])
if qcp2_list:
    q = qcp2_list[0]
    result['qcp2_found'] = True
    result['qcp2_test_type'] = q.get('test_type', '')
    result['qcp2_failure_message'] = strip_html(q.get('failure_message', ''))
    pids = q.get('product_ids', [])
    if pids:
        prods = sr('product.product', [['id', 'in', pids]], ['id', 'name'])
        result['qcp2_product_names'] = [p.get('name', '') for p in prods]
    else:
        result['qcp2_product_names'] = []
else:
    result['qcp2_found'] = False
    result['qcp2_test_type'] = ''
    result['qcp2_failure_message'] = ''
    result['qcp2_product_names'] = []

# 4. Check preventive actions
for alert_name, key in [
    ('Desk Height Adjustment Mechanism Stiff', 'desk_pa'),
    ('Chair Foam Density Below Grade', 'chair_pa'),
]:
    alerts = sr('quality.alert', [['name', '=', alert_name]], ['id', 'preventive_action'])
    if alerts:
        result[key] = strip_html(alerts[0].get('preventive_action', ''))
    else:
        result[key] = ''

with open('/tmp/quality_system_expansion_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export result: {json.dumps(result, indent=2)}")
PYTHON_EOF

echo "=== quality_system_expansion export complete ==="
