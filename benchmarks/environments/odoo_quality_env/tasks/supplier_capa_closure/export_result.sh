#!/bin/bash
echo "=== Exporting supplier_capa_closure results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/supplier_capa_closure_end.png

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
    with open('/tmp/supplier_capa_closure_result.json', 'w') as f:
        json.dump({'error': 'auth_failed'}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

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
    with open('/tmp/supplier_capa_closure_gt.json', 'r') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/supplier_capa_closure_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

target_ids = gt.get('target_alert_ids', [])
done_stage_id = gt.get('done_stage_id')

result = {
    'done_stage_id': done_stage_id,
    'total_target_alerts': len(target_ids),
    'alerts': [],
}

for alert_id in target_ids:
    alerts = sr('quality.alert', [['id', '=', alert_id]],
                ['id', 'name', 'stage_id', 'corrective_action', 'preventive_action'])
    if alerts:
        a = alerts[0]
        stage = a.get('stage_id')
        result['alerts'].append({
            'id': a['id'],
            'name': a.get('name', ''),
            'stage_name': stage[1] if isinstance(stage, (list, tuple)) and len(stage) > 1 else str(stage or ''),
            'stage_id': stage[0] if isinstance(stage, (list, tuple)) else stage,
            'corrective_action': strip_html(a.get('corrective_action', '')),
            'preventive_action': strip_html(a.get('preventive_action', '')),
        })

with open('/tmp/supplier_capa_closure_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export result: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/supplier_capa_closure_result.json 2>/dev/null || true
echo "=== supplier_capa_closure export complete ==="
