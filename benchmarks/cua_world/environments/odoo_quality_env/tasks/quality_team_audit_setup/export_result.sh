#!/bin/bash
echo "=== Exporting quality_team_audit_setup results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/quality_team_audit_setup_end.png

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, time

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
    with open('/tmp/quality_team_audit_setup_result.json', 'w') as f:
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

# Load ground truth
try:
    with open('/tmp/quality_team_audit_setup_gt.json', 'r') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/quality_team_audit_setup_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

new_alert_ids = gt.get('new_alert_ids', [])
safety_critical_ids = gt.get('safety_critical_alert_ids', [])
safety_critical_names = gt.get('safety_critical_names', [])

result = {
    'total_new_alerts': len(new_alert_ids),
    'safety_critical_alert_count': len(safety_critical_ids),
    'safety_critical_names': safety_critical_names,
}

# Check if "ISO Surveillance Response Team" exists
team_records = sr('quality.alert.team', [['name', '=', 'ISO Surveillance Response Team']], ['id', 'name'])
if team_records:
    result['team_found'] = True
    result['team_id'] = team_records[0]['id']
    result['team_name'] = team_records[0]['name']
else:
    result['team_found'] = False
    result['team_id'] = None
    result['team_name'] = ''

# Check how many New-stage alerts are assigned to that team
assigned_to_team_count = 0
alert_details = []
if new_alert_ids and result['team_id']:
    for alert_id in new_alert_ids:
        alerts = sr('quality.alert', [['id', '=', alert_id]], ['id', 'name', 'team_id', 'priority'])
        if alerts:
            a = alerts[0]
            team = a.get('team_id')
            team_id = team[0] if isinstance(team, (list, tuple)) else team
            is_assigned = (team_id == result['team_id'])
            if is_assigned:
                assigned_to_team_count += 1
            alert_details.append({
                'id': a['id'],
                'name': a.get('name', ''),
                'team_id': team_id,
                'assigned_to_target_team': is_assigned,
                'priority': a.get('priority', '0'),
            })

result['assigned_to_team_count'] = assigned_to_team_count
result['alert_details'] = alert_details

# Check safety-critical alert priorities
safety_urgent_count = 0
safety_details = []
for sc_id in safety_critical_ids:
    alerts = sr('quality.alert', [['id', '=', sc_id]], ['id', 'name', 'priority'])
    if alerts:
        a = alerts[0]
        priority = a.get('priority', '0')
        is_urgent = priority in ('2', '3')
        if is_urgent:
            safety_urgent_count += 1
        safety_details.append({
            'id': a['id'],
            'name': a.get('name', ''),
            'priority': priority,
            'is_urgent': is_urgent,
        })

result['safety_urgent_count'] = safety_urgent_count
result['safety_details'] = safety_details

with open('/tmp/quality_team_audit_setup_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export result: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/quality_team_audit_setup_result.json 2>/dev/null || true
echo "=== quality_team_audit_setup export complete ==="
