#!/bin/bash
echo "=== Setting up batch_alert_triage task ==="

source /workspace/scripts/task_utils.sh

# Step 1: CLEAN
rm -f /tmp/batch_alert_triage_result.json
rm -f /tmp/batch_alert_triage_gt.json

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

def sr(model, domain, fields, limit=100):
    return models.execute_kw(db, uid, pwd, model, 'search_read', [domain], {'fields': fields, 'limit': limit})

def w(model, ids, vals):
    return models.execute_kw(db, uid, pwd, model, 'write', [ids, vals])

def d(model, ids):
    return models.execute_kw(db, uid, pwd, model, 'unlink', [ids])

# Get stage IDs
stages = sr('quality.alert.stage', [], ['id', 'name'])
in_progress_id = None
done_id = None
new_id = None
for st in stages:
    nm = st['name'].lower()
    if 'new' in nm or 'open' in nm:
        new_id = st['id']
    if 'progress' in nm:
        in_progress_id = st['id']
    if 'done' in nm or 'close' in nm:
        done_id = st['id']
if not new_id and stages:
    new_id = stages[0]['id']
if not in_progress_id and len(stages) >= 2:
    in_progress_id = stages[1]['id']
if not done_id and stages:
    done_id = stages[-1]['id']

# Reset the three alerts-to-close back to In Progress
for name in [
    'Cabinet Door Hinge Misalignment',
    'Acoustic Panel Bonding Failure',
    'Cabinet Coating Thickness Non-Uniform',
]:
    ids = s('quality.alert', [['name', '=', name]])
    if ids:
        w('quality.alert', ids, {'stage_id': in_progress_id})
        print(f"Reset '{name}' to In Progress stage")

# Reset "Chair Armrest Cracking" to High priority (agent must change to Urgent)
ids = s('quality.alert', [['name', '=', 'Chair Armrest Cracking']])
if ids:
    w('quality.alert', ids, {'priority': '1'})
    print("Reset 'Chair Armrest Cracking' to High priority")

# Reset "Loose Hardware on Shelf Unit" to Normal priority (agent must change to High)
ids = s('quality.alert', [['name', '=', 'Loose Hardware on Shelf Unit']])
if ids:
    w('quality.alert', ids, {'priority': '0'})
    print("Reset 'Loose Hardware on Shelf Unit' to Normal priority")

# Reset "Desk Laminate Delamination" corrective action to empty
ids = s('quality.alert', [['name', '=', 'Desk Laminate Delamination']])
if ids:
    w('quality.alert', ids, {'corrective_action': ''})
    print("Reset 'Desk Laminate Delamination' corrective action to empty")

# Remove target summary alert from prior runs
ids = s('quality.alert', [['name', 'ilike', 'Q4 2024 Quality Review']])
if ids:
    d('quality.alert', ids)
    print("Removed stale 'Q4 2024 Quality Review' alert")

# Save ground truth
gt = {
    'in_progress_stage_id': in_progress_id,
    'done_stage_id': done_id,
    'new_stage_id': new_id,
}
with open('/tmp/batch_alert_triage_gt.json', 'w') as f:
    json.dump(gt, f)
print(f"Ground truth: {gt}")
PYTHON_EOF

# Step 2: RECORD timestamp
date +%s > /tmp/batch_alert_triage_start_ts

# Step 3: Record baseline
record_task_baseline "batch_alert_triage"

# Step 4: Navigate to Odoo home
ensure_firefox "http://localhost:8069/web#action=menu"
sleep 3

take_screenshot /tmp/batch_alert_triage_start.png

echo "=== batch_alert_triage setup complete ==="
