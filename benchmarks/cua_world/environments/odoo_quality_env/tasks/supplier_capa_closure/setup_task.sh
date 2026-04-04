#!/bin/bash
echo "=== Setting up supplier_capa_closure task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/supplier_capa_closure_result.json
rm -f /tmp/supplier_capa_closure_gt.json

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

def sr(model, domain, fields, limit=200):
    return models.execute_kw(db, uid, pwd, model, 'search_read', [domain], {'fields': fields, 'limit': limit})

def w(model, ids, vals):
    return models.execute_kw(db, uid, pwd, model, 'write', [ids, vals])

# Identify stage IDs
stages = sr('quality.alert.stage', [], ['id', 'name'])
in_progress_id = None
done_id = None
for st in stages:
    nm = st['name'].lower()
    if 'progress' in nm:
        in_progress_id = st['id']
    if 'done' in nm or 'close' in nm:
        done_id = st['id']

if not in_progress_id:
    print("ERROR: Could not find 'In Progress' stage", file=sys.stderr)
    sys.exit(1)

# Find all In Progress alerts
in_progress_alerts = sr('quality.alert', [['stage_id', '=', in_progress_id]], ['id', 'name'])
if not in_progress_alerts:
    print("WARNING: No In Progress alerts found — task may be trivially empty", file=sys.stderr)

alert_ids = [a['id'] for a in in_progress_alerts]
alert_info = [{'id': a['id'], 'name': a['name']} for a in in_progress_alerts]

# Clear corrective_action and preventive_action so agent must fill them in
if alert_ids:
    w('quality.alert', alert_ids, {
        'corrective_action': '',
        'preventive_action': '',
        'stage_id': in_progress_id,
    })
    print(f"Cleared CAPA fields on {len(alert_ids)} In Progress alerts: {[a['name'] for a in in_progress_alerts]}")

# Save ground truth for use by export_result.sh
gt = {
    'in_progress_stage_id': in_progress_id,
    'done_stage_id': done_id,
    'target_alert_ids': alert_ids,
    'target_alerts': alert_info,
}
with open('/tmp/supplier_capa_closure_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)
print(f"Ground truth saved: {len(alert_ids)} target alerts")
PYTHON_EOF

date +%s > /tmp/supplier_capa_closure_start_ts

record_task_baseline "supplier_capa_closure"

ensure_firefox "http://localhost:8069/web#action=quality.action_quality_alert"
sleep 3

take_screenshot /tmp/supplier_capa_closure_start.png

echo "=== supplier_capa_closure setup complete ==="
