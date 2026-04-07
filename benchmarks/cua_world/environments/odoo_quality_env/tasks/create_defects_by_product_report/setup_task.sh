#!/bin/bash
set -e
echo "=== Setting up create_defects_by_product_report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create sufficient data for the report to be meaningful
# We need alerts across different products
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import random

url = "http://localhost:8069"
db = "odoo_quality"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, "admin", password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")
    
    # 1. Clean up any existing filter with the target name to prevent false positives
    existing_filters = models.execute_kw(db, uid, password, 'ir.filters', 'search', 
        [[['name', 'ilike', 'Alerts by Product'], ['model_id', '=', 'quality.alert']]])
    if existing_filters:
        models.execute_kw(db, uid, password, 'ir.filters', 'unlink', [existing_filters])
        print(f"Removed {len(existing_filters)} pre-existing filters.")

    # 2. Ensure we have products
    products = models.execute_kw(db, uid, password, 'product.product', 'search_read', 
        [[['sale_ok', '=', True]]], {'fields': ['id', 'name'], 'limit': 5})
        
    if not products:
        print("Error: No products found.")
        sys.exit(1)

    # 3. Create alerts distributed across products
    # We want at least ~8 alerts total
    alert_count = models.execute_kw(db, uid, password, 'quality.alert', 'search_count', [[]])
    
    if alert_count < 8:
        print(f"Current alert count {alert_count} is low. Generating more...")
        for i in range(10):
            prod = random.choice(products)
            models.execute_kw(db, uid, password, 'quality.alert', 'create', [{
                'name': f"Report Test Defect {i} - {prod['name']}",
                'product_id': prod['id'],
                'description': "Auto-generated for pivot report task",
                'priority': random.choice(['0', '1', '2'])
            }])
        print("Created sample alerts.")

except Exception as e:
    print(f"Setup error: {e}", file=sys.stderr)
PYTHON_EOF

# Launch Firefox and navigate to Quality Alerts
# We intentionally go to the list view first so the agent has to switch to Pivot
ensure_firefox "http://localhost:8069/web#action=quality_control.quality_alert_action_team&view_type=list"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="