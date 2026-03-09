#!/bin/bash
echo "=== Exporting batch_alert_triage results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/batch_alert_triage_end.png

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
    with open('/tmp/batch_alert_triage_result.json', 'w') as f:
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
    with open('/tmp/batch_alert_triage_gt.json', 'r') as f:
        gt = json.load(f)
    result['gt_done_stage_id'] = gt.get('done_stage_id')
except Exception:
    result['gt_done_stage_id'] = None

# Check stage transitions for 3 alerts
for alert_name, key in [
    ('Cabinet Door Hinge Misalignment', 'hinge'),
    ('Acoustic Panel Bonding Failure', 'bonding'),
    ('Cabinet Coating Thickness Non-Uniform', 'coating'),
]:
    alerts = sr('quality.alert', [['name', '=', alert_name]], ['id', 'stage_id'])
    if alerts:
        stage = alerts[0].get('stage_id')
        result[f'{key}_stage_name'] = stage[1] if isinstance(stage, (list, tuple)) and len(stage) > 1 else str(stage or '')
        result[f'{key}_stage_id'] = stage[0] if isinstance(stage, (list, tuple)) else stage
    else:
        result[f'{key}_stage_name'] = ''
        result[f'{key}_stage_id'] = None

# Check priority changes
for alert_name, key in [
    ('Chair Armrest Cracking', 'armrest'),
    ('Loose Hardware on Shelf Unit', 'hardware'),
]:
    alerts = sr('quality.alert', [['name', '=', alert_name]], ['id', 'priority'])
    if alerts:
        result[f'{key}_priority'] = alerts[0].get('priority', '')
    else:
        result[f'{key}_priority'] = ''

# Check corrective action on Desk Laminate
dl_alerts = sr('quality.alert', [['name', '=', 'Desk Laminate Delamination']], ['id', 'corrective_action'])
if dl_alerts:
    result['desk_corrective_action'] = strip_html(dl_alerts[0].get('corrective_action', ''))
else:
    result['desk_corrective_action'] = ''

# Check for new summary alert
q4_alerts = sr('quality.alert', [['name', 'ilike', 'Q4 2024 Quality Review']], ['id', 'name', 'description', 'priority'])
if q4_alerts:
    a = q4_alerts[0]
    result['q4_alert_found'] = True
    result['q4_alert_description'] = strip_html(a.get('description', ''))
    result['q4_alert_priority'] = a.get('priority', '')
else:
    result['q4_alert_found'] = False
    result['q4_alert_description'] = ''
    result['q4_alert_priority'] = ''

with open('/tmp/batch_alert_triage_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export result: {json.dumps(result, indent=2)}")
PYTHON_EOF

echo "=== batch_alert_triage export complete ==="
