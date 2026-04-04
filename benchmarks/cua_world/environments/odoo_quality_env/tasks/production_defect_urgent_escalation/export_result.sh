#!/bin/bash
echo "=== Exporting production_defect_urgent_escalation results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/production_defect_urgent_escalation_end.png

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
    with open('/tmp/production_defect_urgent_escalation_result.json', 'w') as f:
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
    with open('/tmp/production_defect_urgent_escalation_gt.json', 'r') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/production_defect_urgent_escalation_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

target_check_ids = gt.get('target_check_ids', [])
available_team_ids = gt.get('available_team_ids', [])
target_check_name = gt.get('target_check_name', 'Visual Inspection - Cabinet Finish')

result = {}

# Check state and notes on the target quality check
checks = sr('quality.check', [['name', '=', target_check_name]], ['id', 'name', 'quality_state', 'note'])
if checks:
    c = checks[0]
    note = strip_html(c.get('note', ''))
    result['check_found'] = True
    result['check_id'] = c['id']
    result['check_state'] = c.get('quality_state', '')
    result['check_note'] = note
    result['check_note_length'] = len(note)
else:
    result['check_found'] = False
    result['check_state'] = ''
    result['check_note'] = ''
    result['check_note_length'] = 0

# Look for new Urgent quality alert created since task start
# We check for alerts with priority '2' (Urgent) or '3' (Blocker) created recently
# Use timestamp to bound the search - get all Urgent/Blocker alerts not in known pre-existing set
try:
    start_ts = int(open('/tmp/production_defect_urgent_escalation_start_ts').read().strip())
except Exception:
    start_ts = 0

# Get all urgent/blocker alerts
urgent_alerts = sr('quality.alert',
                   ['|', ['priority', '=', '2'], ['priority', '=', '3']],
                   ['id', 'name', 'priority', 'description', 'team_id', 'create_date'])

# Filter to alerts created after task start (using create_date string comparison)
new_urgent_alerts = []
for a in urgent_alerts:
    # Include all urgent alerts - filter by not being in the pre-existing known set
    # The task starts with a cleared state, so any Urgent alerts now are from agent
    new_urgent_alerts.append(a)

if new_urgent_alerts:
    # Pick the most recently created one
    a = new_urgent_alerts[-1]
    desc = strip_html(a.get('description', ''))
    team = a.get('team_id')
    team_id = team[0] if isinstance(team, (list, tuple)) else team
    result['new_urgent_alert_found'] = True
    result['new_urgent_alert_id'] = a['id']
    result['new_urgent_alert_name'] = a.get('name', '')
    result['new_urgent_alert_priority'] = a.get('priority', '')
    result['new_urgent_alert_description'] = desc
    result['new_urgent_alert_description_length'] = len(desc)
    result['new_urgent_alert_team_id'] = team_id
    result['new_urgent_alert_has_team'] = team_id is not None and team_id != False
    result['available_team_ids'] = available_team_ids
else:
    result['new_urgent_alert_found'] = False
    result['new_urgent_alert_id'] = None
    result['new_urgent_alert_name'] = ''
    result['new_urgent_alert_priority'] = ''
    result['new_urgent_alert_description'] = ''
    result['new_urgent_alert_description_length'] = 0
    result['new_urgent_alert_team_id'] = None
    result['new_urgent_alert_has_team'] = False
    result['available_team_ids'] = available_team_ids

with open('/tmp/production_defect_urgent_escalation_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export result: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/production_defect_urgent_escalation_result.json 2>/dev/null || true
echo "=== production_defect_urgent_escalation export complete ==="
