#!/bin/bash
# Setup script for analytic_cost_allocation task
# Ensures clean state by removing any existing plan/accounts with the target names.

echo "=== Setting up analytic_cost_allocation ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Use Python to clean up potential previous runs via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    if not uid:
        print("ERROR: Authentication failed!", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Cannot connect to Odoo: {e}", file=sys.stderr)
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Clean up Analytic Accounts
accounts_to_remove = ['Engineering Dept', 'Marketing Dept', 'Operations Dept']
existing_accounts = execute('account.analytic.account', 'search',
    [[['name', 'in', accounts_to_remove]]])
if existing_accounts:
    print(f"Removing {len(existing_accounts)} existing analytic accounts...")
    try:
        execute('account.analytic.account', 'unlink', [existing_accounts])
    except Exception as e:
        print(f"Warning: could not unlink accounts (might be used): {e}")
        # Try renaming them to avoid conflict if unlink fails
        execute('account.analytic.account', 'write', [existing_accounts, {'name': 'ARCHIVED_TASK_ACCOUNT', 'active': False}])

# 2. Clean up Analytic Plan
plan_name = 'Department Costs'
existing_plans = execute('account.analytic.plan', 'search',
    [[['name', '=', plan_name]]])
if existing_plans:
    print(f"Removing existing analytic plan '{plan_name}'...")
    try:
        execute('account.analytic.plan', 'unlink', [existing_plans])
    except Exception as e:
        print(f"Warning: could not unlink plan: {e}")
        execute('account.analytic.plan', 'write', [existing_plans, {'name': 'ARCHIVED_TASK_PLAN', 'active': False}])

# 3. Verify Vendor exists
vendor = execute('res.partner', 'search', [[['name', '=', 'Deco Addict']]])
if not vendor:
    print("Creating vendor 'Deco Addict'...")
    execute('res.partner', 'create', [{'name': 'Deco Addict', 'is_company': True}])
else:
    print("Vendor 'Deco Addict' exists.")

print("Cleanup complete.")
PYEOF

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="