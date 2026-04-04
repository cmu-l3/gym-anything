#!/bin/bash
echo "=== Setting up production_defect_urgent_escalation task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/production_defect_urgent_escalation_result.json
rm -f /tmp/production_defect_urgent_escalation_gt.json

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

# Reset the target quality check back to 'none' state with empty notes
target_check_name = 'Visual Inspection - Cabinet Finish'
check_ids = s('quality.check', [['name', '=', target_check_name]])
if check_ids:
    w('quality.check', check_ids, {'quality_state': 'none', 'note': ''})
    print(f"Reset '{target_check_name}' to none state (ids={check_ids})")
else:
    # Create it if somehow missing
    cabinet_ids = s('product.product', [['name', 'ilike', 'Cabinet with Doors']])
    cabinet_id = cabinet_ids[0] if cabinet_ids else None
    data = {'name': target_check_name, 'quality_state': 'none', 'note': ''}
    if cabinet_id:
        data['product_id'] = cabinet_id
    cid = models.execute_kw(db, uid, pwd, 'quality.check', 'create', [data])
    check_ids = [cid]
    print(f"Created '{target_check_name}' (id={cid})")

# Remove any stale urgent escalation alerts from prior runs
stale = s('quality.alert', [
    ['name', 'ilike', 'Batch Hold'],
    ['priority', '=', '2'],
])
if stale:
    d('quality.alert', stale)
    print(f"Removed stale Urgent Batch Hold alerts (ids={stale})")

# Get existing team IDs for reference
teams = sr('quality.alert.team', [], ['id', 'name'], limit=10)
team_ids = [t['id'] for t in teams]
team_names = [t['name'] for t in teams]

gt = {
    'target_check_name': target_check_name,
    'target_check_ids': check_ids,
    'available_team_ids': team_ids,
    'available_team_names': team_names,
}
with open('/tmp/production_defect_urgent_escalation_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)
print(f"Ground truth: check_ids={check_ids}, teams={team_names}")
PYTHON_EOF

date +%s > /tmp/production_defect_urgent_escalation_start_ts

record_task_baseline "production_defect_urgent_escalation"

ensure_firefox "http://localhost:8069/web#action=quality.action_quality_check"
sleep 3

take_screenshot /tmp/production_defect_urgent_escalation_start.png

echo "=== production_defect_urgent_escalation setup complete ==="
