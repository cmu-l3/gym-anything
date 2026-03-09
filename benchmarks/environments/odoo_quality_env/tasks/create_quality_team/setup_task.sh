#!/bin/bash
echo "=== Setting up create_quality_team task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "create_quality_team"

# Remove any existing team with exact target name for clean start
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_quality'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    existing = models.execute_kw(db, uid, 'admin', 'quality.alert.team', 'search',
                                  [[['name', '=', 'Electronics QA Team']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'quality.alert.team', 'unlink', [existing])
        print(f"Removed existing 'Electronics QA Team' (ids={existing})")
    else:
        print("No existing 'Electronics QA Team' — clean slate")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to Quality > Configuration > Quality Teams
ensure_firefox
sleep 2
navigate_firefox "http://localhost:8069/web#action=quality.action_quality_alert_team"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Quality Teams configuration list."
echo "Agent should create new team named 'Electronics QA Team'."
echo "=== create_quality_team task setup complete ==="
