#!/bin/bash
echo "=== Setting up quality_team_audit_setup task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/quality_team_audit_setup_result.json
rm -f /tmp/quality_team_audit_setup_gt.json

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, time

url = 'http://localhost:8069'
db = 'odoo_quality'
user = 'admin'
pwd = 'admin'

uid = None
for attempt in range(20):
    try:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, user, pwd, {})
        if uid:
            break
    except Exception:
        pass
    time.sleep(5)

if not uid:
    print("ERROR: Could not authenticate to Odoo", file=sys.stderr)
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def s(model, domain):
    return models.execute_kw(db, uid, pwd, model, 'search', [domain])

def sr(model, domain, fields, limit=200):
    return models.execute_kw(db, uid, pwd, model, 'search_read', [domain], {'fields': fields, 'limit': limit})

def w(model, ids, vals):
    return models.execute_kw(db, uid, pwd, model, 'write', [ids, vals])

def d(model, ids):
    return models.execute_kw(db, uid, pwd, model, 'unlink', [ids])

# Remove any stale "ISO Surveillance Response Team" from prior runs
stale_teams = s('quality.alert.team', [['name', '=', 'ISO Surveillance Response Team']])
if stale_teams:
    d('quality.alert.team', stale_teams)
    print(f"Removed stale 'ISO Surveillance Response Team' (ids={stale_teams})")

# Find New stage ID
stages = sr('quality.alert.stage', [], ['id', 'name'])
new_stage_id = None
for st in stages:
    nm = st['name'].lower()
    if 'new' in nm or ('open' in nm and 'progress' not in nm):
        new_stage_id = st['id']
        break
if not new_stage_id and stages:
    new_stage_id = stages[0]['id']

# Find all New-stage alerts and clear their team_id so agent must assign them
new_alerts = sr('quality.alert', [['stage_id', '=', new_stage_id]], ['id', 'name', 'priority'])
new_alert_ids = [a['id'] for a in new_alerts]

if new_alert_ids:
    w('quality.alert', new_alert_ids, {'team_id': False, 'priority': '0'})
    print(f"Cleared team_id and reset priority to Normal for {len(new_alert_ids)} New-stage alerts")

# The 3 safety-critical alerts (structural/hardware/cracking) that should be escalated:
# - "Critical Weld Failure on Frame" (structural)
# - "Loose Hardware on Shelf Unit" (hardware)
# - "Chair Armrest Cracking" (cracking)
safety_critical_names = [
    'Critical Weld Failure on Frame',
    'Loose Hardware on Shelf Unit',
    'Chair Armrest Cracking',
]

safety_critical_ids = []
for name in safety_critical_names:
    ids = s('quality.alert', [['name', '=', name]])
    if ids:
        safety_critical_ids.extend(ids)

alert_info = [{'id': a['id'], 'name': a['name']} for a in new_alerts]

gt = {
    'new_stage_id': new_stage_id,
    'new_alert_ids': new_alert_ids,
    'new_alert_info': alert_info,
    'safety_critical_alert_ids': safety_critical_ids,
    'safety_critical_names': safety_critical_names,
    'target_team_name': 'ISO Surveillance Response Team',
}
with open('/tmp/quality_team_audit_setup_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)
print(f"Ground truth: {len(new_alert_ids)} New-stage alerts, {len(safety_critical_ids)} safety-critical")
PYTHON_EOF

date +%s > /tmp/quality_team_audit_setup_start_ts

record_task_baseline "quality_team_audit_setup"

ensure_firefox "http://localhost:8069/web#action=menu"
sleep 3

take_screenshot /tmp/quality_team_audit_setup_start.png

echo "=== quality_team_audit_setup setup complete ==="
