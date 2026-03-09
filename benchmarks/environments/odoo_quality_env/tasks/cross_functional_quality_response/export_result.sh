#!/bin/bash
echo "=== Exporting cross_functional_quality_response results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/cross_functional_quality_response_end.png

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
    with open('/tmp/cross_functional_quality_response_result.json', 'w') as f:
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

# Load ground truth
try:
    with open('/tmp/cross_functional_quality_response_gt.json', 'r') as f:
        gt = json.load(f)
    result['gt_in_progress_stage_id'] = gt.get('in_progress_stage_id')
except Exception:
    result['gt_in_progress_stage_id'] = None

# 1. Check for main alert
alerts = sr('quality.alert', [['name', 'ilike', 'Field Failure']],
            ['id', 'name', 'product_id', 'priority', 'description',
             'corrective_action', 'preventive_action'])
if alerts:
    a = alerts[0]
    result['alert_found'] = True
    result['alert_name'] = a.get('name', '')
    product = a.get('product_id')
    result['alert_product_name'] = product[1] if isinstance(product, (list, tuple)) and len(product) > 1 else str(product or '')
    result['alert_priority'] = a.get('priority', '')
    result['alert_description'] = strip_html(a.get('description', ''))
    result['alert_corrective_action'] = strip_html(a.get('corrective_action', ''))
    result['alert_preventive_action'] = strip_html(a.get('preventive_action', ''))
else:
    result['alert_found'] = False
    result['alert_name'] = ''
    result['alert_product_name'] = ''
    result['alert_priority'] = ''
    result['alert_description'] = ''
    result['alert_corrective_action'] = ''
    result['alert_preventive_action'] = ''

# 2. Check QCP "Bracket Integrity"
qcps = sr('quality.point', [['name', 'ilike', 'Bracket Integrity']],
          ['id', 'name', 'product_ids', 'test_type', 'failure_message'])
if qcps:
    q = qcps[0]
    result['qcp_found'] = True
    result['qcp_test_type'] = q.get('test_type', '')
    result['qcp_failure_message'] = strip_html(q.get('failure_message', ''))
    pids = q.get('product_ids', [])
    if pids:
        prods = sr('product.product', [['id', 'in', pids]], ['id', 'name'])
        result['qcp_product_names'] = [p.get('name', '') for p in prods]
    else:
        result['qcp_product_names'] = []
else:
    result['qcp_found'] = False
    result['qcp_test_type'] = ''
    result['qcp_failure_message'] = ''
    result['qcp_product_names'] = []

# 3. Check "Screen Frame Scratch" stage
sf = sr('quality.alert', [['name', '=', 'Screen Frame Scratch on Delivery']], ['id', 'stage_id'])
if sf:
    stage = sf[0].get('stage_id')
    result['sf_stage_name'] = stage[1] if isinstance(stage, (list, tuple)) and len(stage) > 1 else str(stage or '')
    result['sf_stage_id'] = stage[0] if isinstance(stage, (list, tuple)) else stage
else:
    result['sf_stage_name'] = ''
    result['sf_stage_id'] = None

# 4. Check "Screen Colour Uniformity Audit" state
cu = sr('quality.check', [['name', '=', 'Screen Colour Uniformity Audit']], ['id', 'quality_state'])
if cu:
    result['cu_state'] = cu[0].get('quality_state', '')
else:
    result['cu_state'] = ''

# 5. Check for new check "Bracket UT Inspection"
bt = sr('quality.check', [['name', 'ilike', 'Bracket UT Inspection']], ['id', 'name', 'quality_state', 'product_id'])
if bt:
    result['bracket_check_found'] = True
    result['bracket_check_state'] = bt[0].get('quality_state', '')
    prod = bt[0].get('product_id')
    result['bracket_check_product'] = prod[1] if isinstance(prod, (list, tuple)) and len(prod) > 1 else str(prod or '')
else:
    result['bracket_check_found'] = False
    result['bracket_check_state'] = ''
    result['bracket_check_product'] = ''

with open('/tmp/cross_functional_quality_response_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export result: {json.dumps(result, indent=2)}")
PYTHON_EOF

echo "=== cross_functional_quality_response export complete ==="
