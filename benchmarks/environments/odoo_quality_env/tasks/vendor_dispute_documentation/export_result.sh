#!/bin/bash
echo "=== Exporting vendor_dispute_documentation results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/vendor_dispute_documentation_end.png

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
    with open('/tmp/vendor_dispute_documentation_result.json', 'w') as f:
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
    with open('/tmp/vendor_dispute_documentation_gt.json', 'r') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/vendor_dispute_documentation_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

alert_id = gt.get('target_alert_id')
screen_id = gt.get('screen_product_id')
available_partners = gt.get('available_partner_ids', [])

result = {
    'target_alert_id': alert_id,
    'available_partner_count': len(available_partners),
}

# Read the target alert state
if alert_id:
    alerts = sr('quality.alert', [['id', '=', alert_id]],
                ['id', 'name', 'stage_id', 'priority', 'corrective_action',
                 'preventive_action', 'partner_id'])
    if alerts:
        a = alerts[0]
        stage = a.get('stage_id')
        partner = a.get('partner_id')
        ca = strip_html(a.get('corrective_action', ''))
        pa = strip_html(a.get('preventive_action', ''))
        result['alert_found'] = True
        result['alert_name'] = a.get('name', '')
        result['stage_name'] = stage[1] if isinstance(stage, (list, tuple)) and len(stage) > 1 else str(stage or '')
        result['stage_id'] = stage[0] if isinstance(stage, (list, tuple)) else stage
        result['priority'] = a.get('priority', '0')
        result['corrective_action'] = ca
        result['preventive_action'] = pa
        result['partner_id'] = partner[0] if isinstance(partner, (list, tuple)) else partner
        result['partner_name'] = partner[1] if isinstance(partner, (list, tuple)) and len(partner) > 1 else ''
        result['has_partner'] = bool(result['partner_id'])
    else:
        result['alert_found'] = False
        result['stage_name'] = ''
        result['stage_id'] = None
        result['priority'] = '0'
        result['corrective_action'] = ''
        result['preventive_action'] = ''
        result['partner_id'] = None
        result['partner_name'] = ''
        result['has_partner'] = False
else:
    result['alert_found'] = False

# Check for new Pass/Fail QCP for Acoustic Bloc Screens
# Look for passfail QCPs associated with the screen product
pf_qcps = sr('quality.point', [['test_type', '=', 'passfail']],
             ['id', 'name', 'failure_message', 'test_type', 'product_ids'])
if not pf_qcps:
    # Try alternate field value
    pf_qcps = sr('quality.point', [['test_type', 'ilike', 'pass']],
                 ['id', 'name', 'failure_message', 'test_type', 'product_ids'])

# Find one for Acoustic Bloc Screens
new_pf_qcp = None
for qcp in pf_qcps:
    prod_ids = qcp.get('product_ids', [])
    if screen_id and screen_id in prod_ids:
        new_pf_qcp = qcp
        break
    if 'coating' in (qcp.get('name') or '').lower() or 'acoustic' in (qcp.get('name') or '').lower():
        if new_pf_qcp is None:
            new_pf_qcp = qcp

# Fallback: search by name keywords
if not new_pf_qcp:
    candidates = sr('quality.point',
                    ['|', ['name', 'ilike', 'Acoustic'], ['name', 'ilike', 'Coating']],
                    ['id', 'name', 'failure_message', 'test_type', 'product_ids'])
    # Filter to passfail types
    for qcp in candidates:
        tt = str(qcp.get('test_type', '')).lower()
        if 'pass' in tt or 'fail' in tt:
            new_pf_qcp = qcp
            break
    if not new_pf_qcp and candidates:
        # Any new QCP is better than none
        new_pf_qcp = candidates[0]

if new_pf_qcp:
    fm = strip_html(new_pf_qcp.get('failure_message', ''))
    tt = str(new_pf_qcp.get('test_type', '')).lower()
    result['new_passfail_qcp_found'] = True
    result['new_passfail_qcp_id'] = new_pf_qcp['id']
    result['new_passfail_qcp_name'] = new_pf_qcp.get('name', '')
    result['new_passfail_qcp_test_type'] = new_pf_qcp.get('test_type', '')
    result['new_passfail_qcp_is_passfail'] = 'pass' in tt or 'fail' in tt
    result['new_passfail_qcp_failure_message'] = fm
    result['new_passfail_qcp_has_failure_message'] = len(fm) >= 10
else:
    result['new_passfail_qcp_found'] = False
    result['new_passfail_qcp_id'] = None
    result['new_passfail_qcp_name'] = ''
    result['new_passfail_qcp_test_type'] = ''
    result['new_passfail_qcp_is_passfail'] = False
    result['new_passfail_qcp_failure_message'] = ''
    result['new_passfail_qcp_has_failure_message'] = False

with open('/tmp/vendor_dispute_documentation_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export result: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/vendor_dispute_documentation_result.json 2>/dev/null || true
echo "=== vendor_dispute_documentation export complete ==="
