#!/bin/bash
echo "=== Exporting supplier_nonconformance_response results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/supplier_nonconformance_response_end.png

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
    # Write empty result so verifier scores 0
    with open('/tmp/supplier_nonconformance_response_result.json', 'w') as f:
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

# 1. Check for new team
teams = sr('quality.alert.team', [['name', '=', 'Supplier Nonconformance Review Board']], ['id', 'name'])
result['team_found'] = len(teams) > 0

# 2. Check for new alert
alerts = sr('quality.alert', [['name', 'ilike', 'Systematic Dimensional Variance']],
            ['id', 'name', 'product_id', 'priority', 'corrective_action', 'preventive_action'])
if alerts:
    a = alerts[0]
    result['alert_found'] = True
    result['alert_name'] = a.get('name', '')
    product = a.get('product_id')
    result['alert_product_name'] = product[1] if isinstance(product, (list, tuple)) and len(product) > 1 else str(product or '')
    result['alert_priority'] = a.get('priority', '')
    result['alert_corrective_action'] = strip_html(a.get('corrective_action', ''))
    result['alert_preventive_action'] = strip_html(a.get('preventive_action', ''))
else:
    result['alert_found'] = False
    result['alert_name'] = ''
    result['alert_product_name'] = ''
    result['alert_priority'] = ''
    result['alert_corrective_action'] = ''
    result['alert_preventive_action'] = ''

# 3. Check "Material Hardness Below Specification" stage
mh_alerts = sr('quality.alert', [['name', '=', 'Material Hardness Below Specification']], ['id', 'stage_id'])
if mh_alerts:
    stage = mh_alerts[0].get('stage_id')
    result['mh_stage_name'] = stage[1] if isinstance(stage, (list, tuple)) and len(stage) > 1 else str(stage or '')
    result['mh_stage_id'] = stage[0] if isinstance(stage, (list, tuple)) else stage
else:
    result['mh_stage_name'] = ''
    result['mh_stage_id'] = None

# 4. Check "Screen Frame Scratch on Delivery" priority
sf_alerts = sr('quality.alert', [['name', '=', 'Screen Frame Scratch on Delivery']], ['id', 'priority'])
if sf_alerts:
    result['sf_priority'] = sf_alerts[0].get('priority', '')
else:
    result['sf_priority'] = ''

# Load ground truth
try:
    with open('/tmp/supplier_nonconformance_response_gt.json', 'r') as f:
        gt = json.load(f)
    result['gt_in_progress_stage_id'] = gt.get('in_progress_stage_id')
except Exception:
    result['gt_in_progress_stage_id'] = None

with open('/tmp/supplier_nonconformance_response_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export result: {json.dumps(result, indent=2)}")
PYTHON_EOF

echo "=== supplier_nonconformance_response export complete ==="
