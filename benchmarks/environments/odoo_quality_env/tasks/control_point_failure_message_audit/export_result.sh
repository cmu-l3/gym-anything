#!/bin/bash
echo "=== Exporting control_point_failure_message_audit results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/control_point_failure_message_audit_end.png

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
    with open('/tmp/control_point_failure_message_audit_result.json', 'w') as f:
        json.dump({'error': 'auth_failed'}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def s(model, domain):
    try:
        return models.execute_kw(db, uid, pwd, model, 'search', [domain])
    except Exception:
        return []

def sr(model, domain, fields, limit=200):
    try:
        return models.execute_kw(db, uid, pwd, model, 'search_read', [domain], {'fields': fields, 'limit': limit})
    except Exception:
        return []

def strip_html(html_str):
    if not html_str:
        return ''
    return re.sub(r'<[^>]+>', '', str(html_str)).strip()

# Load ground truth
try:
    with open('/tmp/control_point_failure_message_audit_gt.json', 'r') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/control_point_failure_message_audit_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

target_qcp_names = gt.get('target_qcp_names', [])
desk_product_id = gt.get('desk_product_id')

result = {
    'total_target_qcps': len(target_qcp_names),
    'qcp_details': [],
}

# Check failure_message on target QCPs
filled_count = 0
for name in target_qcp_names:
    qcps = sr('quality.point', [['name', '=', name]], ['id', 'name', 'failure_message'])
    if qcps:
        q = qcps[0]
        fm = strip_html(q.get('failure_message', ''))
        has_message = len(fm) >= 10
        if has_message:
            filled_count += 1
        result['qcp_details'].append({
            'name': name,
            'id': q['id'],
            'failure_message': fm,
            'has_failure_message': has_message,
        })
    else:
        result['qcp_details'].append({
            'name': name,
            'id': None,
            'failure_message': '',
            'has_failure_message': False,
        })

result['filled_count'] = filled_count

# Check for new Measure-type QCP for Customizable Desk
# Look for any QCP associated with the Customizable Desk product that wasn't there before setup
# and has test_type indicating measure
new_measure_qcp = None

# Try test_type as selection field first
measure_qcps = sr('quality.point', [['test_type', '=', 'measure']], ['id', 'name', 'failure_message', 'test_type', 'product_ids'])
# Also try common variant
if not measure_qcps:
    measure_qcps = sr('quality.point', [['test_type', 'ilike', 'measure']], ['id', 'name', 'failure_message', 'test_type', 'product_ids'])

# Find one associated with Customizable Desk
for qcp in measure_qcps:
    prod_ids = qcp.get('product_ids', [])
    if desk_product_id and desk_product_id in prod_ids:
        new_measure_qcp = qcp
        break
    # Also check by name if no product association (agent may not have linked)
    if 'desk' in (qcp.get('name') or '').lower() or 'height' in (qcp.get('name') or '').lower():
        if new_measure_qcp is None:
            new_measure_qcp = qcp

# Fallback: look for any new QCP with "desk" or "height" in name
if not new_measure_qcp:
    desk_qcps = sr('quality.point',
                   [['name', 'ilike', 'desk'], ['name', 'ilike', 'height']],
                   ['id', 'name', 'failure_message', 'test_type'])
    if not desk_qcps:
        desk_qcps = sr('quality.point',
                       ['|', ['name', 'ilike', 'Desk Height'], ['name', 'ilike', 'Height Adjustment']],
                       ['id', 'name', 'failure_message', 'test_type'])
    if desk_qcps:
        new_measure_qcp = desk_qcps[0]

if new_measure_qcp:
    fm = strip_html(new_measure_qcp.get('failure_message', ''))
    result['new_measure_qcp_found'] = True
    result['new_measure_qcp_id'] = new_measure_qcp['id']
    result['new_measure_qcp_name'] = new_measure_qcp.get('name', '')
    result['new_measure_qcp_test_type'] = new_measure_qcp.get('test_type', '')
    result['new_measure_qcp_failure_message'] = fm
    result['new_measure_qcp_has_failure_message'] = len(fm) >= 10
    # Check if it's actually a measure type
    tt = str(new_measure_qcp.get('test_type', '')).lower()
    result['new_measure_qcp_is_measure_type'] = 'measure' in tt
else:
    result['new_measure_qcp_found'] = False
    result['new_measure_qcp_id'] = None
    result['new_measure_qcp_name'] = ''
    result['new_measure_qcp_test_type'] = ''
    result['new_measure_qcp_failure_message'] = ''
    result['new_measure_qcp_has_failure_message'] = False
    result['new_measure_qcp_is_measure_type'] = False

with open('/tmp/control_point_failure_message_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export result: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/control_point_failure_message_audit_result.json 2>/dev/null || true
echo "=== control_point_failure_message_audit export complete ==="
