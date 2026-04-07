#!/bin/bash
echo "=== Exporting supplier_nonconformance_capa_protocol results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/supplier_nonconformance_capa_end.png

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
    with open('/tmp/supplier_nonconformance_capa_result.json', 'w') as f:
        json.dump({'error': 'auth_failed'}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def sr(model, domain, fields, limit=100):
    try:
        return models.execute_kw(db, uid, pwd, model, 'search_read', [domain],
                                 {'fields': fields, 'limit': limit})
    except Exception:
        return []

def strip_html(html_str):
    if not html_str:
        return ''
    return re.sub(r'<[^>]+>', '', str(html_str)).strip()

# Load ground truth
try:
    with open('/tmp/supplier_nonconformance_capa_gt.json', 'r') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/supplier_nonconformance_capa_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

result = {}

# ---------- 1. Quality check state ----------
checks = sr('quality.check',
            [['name', '=', 'Visual Inspection - Cabinet Finish']],
            ['id', 'quality_state'])
if checks:
    result['check_found'] = True
    result['check_state'] = checks[0].get('quality_state', '')
else:
    result['check_found'] = False
    result['check_state'] = ''

# ---------- 2. Quality alert ----------
# Field names: corrective_action, preventive_action (verified from fields_get)
alerts = sr('quality.alert',
            [['name', 'ilike', 'Lot NCR-2024-1247']],
            ['id', 'name', 'product_id', 'partner_id', 'priority',
             'stage_id', 'team_id', 'corrective_action', 'preventive_action'])
if alerts:
    a = alerts[0]
    result['alert_found'] = True
    result['alert_name'] = a.get('name', '')
    # product_id is Many2one: [id, name] or False
    prod = a.get('product_id', False)
    result['alert_product_id'] = prod[0] if isinstance(prod, (list, tuple)) else None
    result['alert_product_name'] = prod[1] if isinstance(prod, (list, tuple)) else ''
    # partner_id (vendor)
    partner = a.get('partner_id', False)
    result['alert_partner_id'] = partner[0] if isinstance(partner, (list, tuple)) else None
    result['alert_partner_name'] = partner[1] if isinstance(partner, (list, tuple)) else ''
    # priority
    result['alert_priority'] = a.get('priority', '0')
    # stage
    stage = a.get('stage_id', False)
    result['alert_stage_id'] = stage[0] if isinstance(stage, (list, tuple)) else None
    result['alert_stage_name'] = stage[1] if isinstance(stage, (list, tuple)) else ''
    # team
    team = a.get('team_id', False)
    result['alert_team_id'] = team[0] if isinstance(team, (list, tuple)) else None
    result['alert_team_name'] = team[1] if isinstance(team, (list, tuple)) else ''
    # corrective / preventive actions
    result['alert_corrective'] = strip_html(a.get('corrective_action', ''))
    result['alert_preventive'] = strip_html(a.get('preventive_action', ''))
else:
    result['alert_found'] = False

# ---------- 3. Quality alert team ----------
teams = sr('quality.alert.team',
           [['name', '=', 'Supplier Incident Response']],
           ['id', 'name'])
if teams:
    result['team_found'] = True
    result['team_id'] = teams[0]['id']
    result['team_name'] = teams[0]['name']
else:
    result['team_found'] = False
    result['team_id'] = None

# ---------- 4. Measure QCP ----------
qcp1_list = sr('quality.point',
               [['name', 'ilike', 'Weld Integrity Verification']],
               ['id', 'name', 'test_type', 'product_ids', 'picking_type_ids',
                'note', 'failure_message'])
if qcp1_list:
    q = qcp1_list[0]
    result['measure_qcp_found'] = True
    result['measure_qcp_name'] = q.get('name', '')
    result['measure_qcp_test_type'] = q.get('test_type', '')
    result['measure_qcp_note'] = strip_html(q.get('note', ''))
    result['measure_qcp_failure_message'] = strip_html(q.get('failure_message', ''))
    # products
    pids = q.get('product_ids', [])
    if pids:
        prods = sr('product.product', [['id', 'in', pids]], ['id', 'name'])
        result['measure_qcp_product_names'] = [pr.get('name', '') for pr in prods]
    else:
        result['measure_qcp_product_names'] = []
    # picking types
    result['measure_qcp_picking_type_ids'] = q.get('picking_type_ids', [])
else:
    result['measure_qcp_found'] = False

# ---------- 5. Pass-Fail QCP ----------
qcp2_list = sr('quality.point',
               [['name', 'ilike', 'Surface Finish Gate']],
               ['id', 'name', 'test_type', 'product_ids', 'picking_type_ids',
                'failure_message'])
if qcp2_list:
    q = qcp2_list[0]
    result['passfail_qcp_found'] = True
    result['passfail_qcp_name'] = q.get('name', '')
    result['passfail_qcp_test_type'] = q.get('test_type', '')
    result['passfail_qcp_failure_message'] = strip_html(q.get('failure_message', ''))
    # products
    pids = q.get('product_ids', [])
    if pids:
        prods = sr('product.product', [['id', 'in', pids]], ['id', 'name'])
        result['passfail_qcp_product_names'] = [pr.get('name', '') for pr in prods]
    else:
        result['passfail_qcp_product_names'] = []
    # picking types
    result['passfail_qcp_picking_type_ids'] = q.get('picking_type_ids', [])
else:
    result['passfail_qcp_found'] = False

# ---------- Include ground truth references for verifier ----------
result['gt_gemini_id'] = gt.get('gemini_id')
result['gt_cabinet_id'] = gt.get('cabinet_id')
result['gt_screens_id'] = gt.get('screens_id')
result['gt_done_stage_id'] = gt.get('stage_ids', {}).get('done')

with open('/tmp/supplier_nonconformance_capa_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export complete: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/supplier_nonconformance_capa_result.json 2>/dev/null || true
echo "=== supplier_nonconformance_capa_protocol export complete ==="
