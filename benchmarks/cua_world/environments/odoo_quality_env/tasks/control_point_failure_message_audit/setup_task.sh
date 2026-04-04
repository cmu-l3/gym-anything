#!/bin/bash
echo "=== Setting up control_point_failure_message_audit task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/control_point_failure_message_audit_result.json
rm -f /tmp/control_point_failure_message_audit_gt.json

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

# Set failure_message for "Final Assembly Audit" and "Chair Stability Load Test"
# so they appear complete, leaving 3 QCPs for the agent to fix
pre_filled = [
    ('Final Assembly Audit', 'Assembly incomplete or out of specification. Reject batch and quarantine. Raise a quality alert immediately and notify production supervisor.'),
    ('Chair Stability Load Test', 'Static load test failed. Do not release units. Quarantine batch and escalate to engineering for structural review.'),
]
for name, msg in pre_filled:
    ids = s('quality.point', [['name', '=', name]])
    if ids:
        w('quality.point', ids, {'failure_message': msg})
        print(f"Pre-filled failure_message on '{name}'")

# Clear failure_message for the 3 target QCPs (the ones agent must fix)
target_qcp_names = [
    'Incoming Parts Verification',
    'Screen Dimensional Inspection',
    'Desk Surface Flatness Check',
]
target_qcp_ids = []
for name in target_qcp_names:
    ids = s('quality.point', [['name', '=', name]])
    if ids:
        w('quality.point', ids, {'failure_message': ''})
        target_qcp_ids.extend(ids)
        print(f"Cleared failure_message on '{name}' (id={ids})")
    else:
        print(f"WARNING: QCP '{name}' not found", file=sys.stderr)

# Remove any stale measure QCP for Customizable Desk height check from prior runs
stale = s('quality.point', [['name', 'ilike', 'Height Adjustment'], ['name', 'ilike', 'Desk']])
if stale:
    d('quality.point', stale)
    print(f"Removed stale Desk height QCP (ids={stale})")

# Also remove by broader search for the new QCP
stale2 = s('quality.point', [['name', 'ilike', 'Desk Height']])
if stale2:
    d('quality.point', stale2)
    print(f"Removed additional stale Desk Height QCPs")

# Get Customizable Desk product ID for GT reference
desk_ids = s('product.product', [['name', 'ilike', 'Customizable Desk']])
desk_product_id = desk_ids[0] if desk_ids else None

gt = {
    'target_qcp_names': target_qcp_names,
    'target_qcp_ids': target_qcp_ids,
    'desk_product_id': desk_product_id,
    'new_qcp_keyword': 'Desk',
}
with open('/tmp/control_point_failure_message_audit_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)
print(f"Ground truth saved: {len(target_qcp_ids)} target QCPs to fix, desk_product_id={desk_product_id}")
PYTHON_EOF

date +%s > /tmp/control_point_failure_message_audit_start_ts

record_task_baseline "control_point_failure_message_audit"

ensure_firefox "http://localhost:8069/web#action=quality.action_quality_point"
sleep 3

take_screenshot /tmp/control_point_failure_message_audit_start.png

echo "=== control_point_failure_message_audit setup complete ==="
