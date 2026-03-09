#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up enable_recurring_revenue task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Ensure clean state: Disable recurring revenues and remove artifacts
python3 - <<PYEOF
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, password, {})
    if not uid:
        print("Authentication failed")
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    print("Cleaning up data artifacts...")
    
    # 1. Delete the specific opportunity if it exists
    leads = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', 'Apex Logic - Enterprise Bundle']]])
    if leads:
        models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [leads])
        print(f"Deleted {len(leads)} stale opportunities")

    # 2. Delete 'Quarterly' plan if it exists
    # Note: The model crm.recurring.plan might not allow deletion if referenced, or might not exist if module uninstalled
    try:
        plans = models.execute_kw(db, uid, password, 'crm.recurring.plan', 'search', [[['name', '=', 'Quarterly']]])
        if plans:
            models.execute_kw(db, uid, password, 'crm.recurring.plan', 'unlink', [plans])
            print(f"Deleted {len(plans)} stale plans")
    except Exception as e:
        print(f"Plan cleanup check skipped (normal if feature disabled): {e}")

    # 3. Attempt to disable the Recurring Revenues setting
    # We do this by creating a config setting record and executing it
    # group_use_recurring_revenues is the field name
    try:
        # Check if currently enabled
        # We can check if the menu item or model is accessible, or check res.config.settings
        # Easiest is to force disable it.
        print("Disabling Recurring Revenues setting...")
        settings_id = models.execute_kw(db, uid, password, 'res.config.settings', 'create', 
            [{'group_use_recurring_revenues': False}])
        models.execute_kw(db, uid, password, 'res.config.settings', 'execute', [[settings_id]])
        print("Settings updated: Recurring Revenues DISABLED")
    except Exception as e:
        print(f"Warning: Could not disable recurring revenues: {e}")

except Exception as e:
    print(f"Setup error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Launch Firefox and log in
ensure_odoo_logged_in "http://localhost:8069/web"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="