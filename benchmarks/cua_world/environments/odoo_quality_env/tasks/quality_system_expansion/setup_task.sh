#!/bin/bash
echo "=== Setting up quality_system_expansion task ==="

source /workspace/scripts/task_utils.sh

# Step 1: CLEAN
rm -f /tmp/quality_system_expansion_result.json

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

def w(model, ids, vals):
    return models.execute_kw(db, uid, pwd, model, 'write', [ids, vals])

def d(model, ids):
    return models.execute_kw(db, uid, pwd, model, 'unlink', [ids])

# CLEAN: Remove target team
team_ids = s('quality.alert.team', [['name', '=', 'Product Line B - Compliance Unit']])
if team_ids:
    d('quality.alert.team', team_ids)
    print("Removed stale team")

# CLEAN: Remove target QCPs
for qcp_name in ['Surface Finish Verification', 'Load-Bearing Capacity Test']:
    ids = s('quality.point', [['name', '=', qcp_name]])
    if ids:
        d('quality.point', ids)
        print(f"Removed stale QCP '{qcp_name}'")

# Reset preventive actions on target alerts to empty
for name in [
    'Desk Height Adjustment Mechanism Stiff',
    'Chair Foam Density Below Grade',
]:
    ids = s('quality.alert', [['name', '=', name]])
    if ids:
        w('quality.alert', ids, {'preventive_action': ''})
        print(f"Reset preventive action on '{name}' to empty")

print("Setup cleanup complete")
PYTHON_EOF

# Step 2: RECORD timestamp
date +%s > /tmp/quality_system_expansion_start_ts

# Step 3: Record baseline
record_task_baseline "quality_system_expansion"

# Step 4: Navigate to Odoo home
ensure_firefox "http://localhost:8069/web#action=menu"
sleep 3

take_screenshot /tmp/quality_system_expansion_start.png

echo "=== quality_system_expansion setup complete ==="
