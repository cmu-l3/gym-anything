#!/bin/bash
set -e
echo "=== Setting up export_high_priority_alerts_csv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean Downloads directory to ensure we verify the correct file
rm -f /home/ga/Downloads/*.csv
rm -f /home/ga/Downloads/*.xls*

# Setup data via Python
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import time

url = "http://localhost:8069"
db = "odoo_quality"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # 1. Get or Create Quality Team
    team_ids = models.execute_kw(db, uid, password, 'quality.alert.team', 'search', [[['name', '=', 'Quality Control Team']]])
    if team_ids:
        team_id = team_ids[0]
    else:
        team_id = models.execute_kw(db, uid, password, 'quality.alert.team', 'create', [{'name': 'Quality Control Team'}])
    
    # 2. Get or Create Product "Office Chair"
    # Search for variant first
    prod_ids = models.execute_kw(db, uid, password, 'product.product', 'search', [[['name', 'ilike', 'Office Chair']]])
    if prod_ids:
        product_id = prod_ids[0]
    else:
        # Create template then get variant
        tmpl_id = models.execute_kw(db, uid, password, 'product.template', 'create', [{'name': 'Office Chair', 'type': 'product'}])
        prod_ids = models.execute_kw(db, uid, password, 'product.product', 'search', [[['product_tmpl_id', '=', tmpl_id]]])
        product_id = prod_ids[0]

    # 3. Clean up existing alerts for this product to avoid confusion
    old_alerts = models.execute_kw(db, uid, password, 'quality.alert', 'search', [[['product_id', '=', product_id]]])
    if old_alerts:
        models.execute_kw(db, uid, password, 'quality.alert', 'unlink', [old_alerts])
        print(f"Cleaned up {len(old_alerts)} existing alerts for Office Chair")

    # 4. Create Task Specific Alerts
    # High Priority (3 stars)
    models.execute_kw(db, uid, password, 'quality.alert', 'create', [{
        'name': 'URGENT: Frame crack on weld B',
        'product_id': product_id,
        'team_id': team_id,
        'priority': '3', 
        'description': 'Critical structural failure detected during stress test.'
    }, {
        'name': 'URGENT: Fabric mismatch batch 99',
        'product_id': product_id,
        'team_id': team_id,
        'priority': '3',
        'description': 'Fabric color deviation > 5 delta E.'
    }])

    # Normal Priority (0 stars)
    models.execute_kw(db, uid, password, 'quality.alert', 'create', [{
        'name': 'Minor scratch on leg',
        'product_id': product_id,
        'team_id': team_id,
        'priority': '0',
        'description': 'Cosmetic defect, acceptable within tolerance class B.'
    }])

    print("Created 2 High Priority and 1 Normal Priority alerts for Office Chair")

except Exception as e:
    print(f"Error setting up data: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is open and on the Quality Alerts page
ensure_firefox "http://localhost:8069/web#action=quality.quality_alert_action_team&view_type=list"

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="