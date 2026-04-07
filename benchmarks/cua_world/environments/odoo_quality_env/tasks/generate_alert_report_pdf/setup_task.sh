#!/bin/bash
set -e
echo "=== Setting up task: generate_alert_report_pdf ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up Downloads to ensure clean state
# This is critical so we don't detect old files
rm -rf /home/ga/Downloads/*
mkdir -p /home/ga/Downloads

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Create the target Quality Alert via XML-RPC
# We use Python to interact with Odoo explicitly to ensure the record exists
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys, time

url = "http://localhost:8069"
db = "odoo_quality"
password = "admin"
uid = 2  # admin uid

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    # Authenticate
    uid = common.authenticate(db, "admin", password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # Clean up any existing alert with this name to avoid ambiguity
    alert_name = 'Structural Crack - Desk Frame'
    existing_ids = models.execute_kw(db, uid, password, 'quality.alert', 'search', [[['name', '=', alert_name]]])
    if existing_ids:
        models.execute_kw(db, uid, password, 'quality.alert', 'unlink', [existing_ids])
        print(f"Removed {len(existing_ids)} existing alerts named '{alert_name}'")

    # Get Product (Customizable Desk)
    prod_ids = models.execute_kw(db, uid, password, 'product.product', 'search', [[['name', 'ilike', 'Customizable Desk']]])
    prod_id = prod_ids[0] if prod_ids else False
    
    # Get Team
    team_ids = models.execute_kw(db, uid, password, 'quality.alert.team', 'search', [[]])
    team_id = team_ids[0] if team_ids else False

    # Get 'New' Stage
    stage_ids = models.execute_kw(db, uid, password, 'quality.alert.stage', 'search', [[['name', 'ilike', 'New']]])
    stage_id = stage_ids[0] if stage_ids else False

    # Create Alert
    alert_vals = {
        'name': alert_name,
        'product_id': prod_id,
        'team_id': team_id,
        'stage_id': stage_id,
        'description': '<p>SEVERE SAFETY ISSUE: Hairline fracture detected near weld point B during stress testing.</p>',
        'priority': '1',  # High priority (stars)
    }
    
    aid = models.execute_kw(db, uid, password, 'quality.alert', 'create', [alert_vals])
    print(f"Created alert '{alert_name}' with ID {aid}")

except Exception as e:
    print(f"Error creating data: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# 4. Launch Firefox and navigate to Quality Alerts
# We use ensure_firefox from task_utils.sh which handles window management
ensure_firefox "http://localhost:8069/web#action=quality.quality_alert_action_team"

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="