#!/bin/bash
source /workspace/scripts/task_utils.sh
set -e

echo "=== Setting up task: create_product_filter ==="

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Setup test data: Ensure Office Chair exists, create specific alerts, clean old filters
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys, time

url = "http://localhost:8069"
db = "odoo_quality"
user = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, user, password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # 1. Clean up any existing 'Chairs Only' filters to prevent false positives from previous runs
    existing_filters = models.execute_kw(db, uid, password, "ir.filters", "search", 
        [[["name", "=", "Chairs Only"], ["model_id", "=", "quality.alert"]]])
    if existing_filters:
        models.execute_kw(db, uid, password, "ir.filters", "unlink", [existing_filters])
        print(f"Cleaned up {len(existing_filters)} existing filters.")

    # 2. Get Product IDs
    chairs = models.execute_kw(db, uid, password, "product.product", "search", [[["name", "ilike", "Office Chair"]]])
    cabinets = models.execute_kw(db, uid, password, "product.product", "search", [[["name", "ilike", "Cabinet"]]])
    
    chair_id = chairs[0] if chairs else False
    cabinet_id = cabinets[0] if cabinets else False
    
    if not chair_id:
        print("Error: Office Chair not found", file=sys.stderr)
        sys.exit(1)

    # 3. Create Alert for Chair (The Target)
    # Check if exists first to avoid clutter
    existing_chair_alert = models.execute_kw(db, uid, password, "quality.alert", "search", 
        [[["name", "=", "Wobbly Wheel - Office Chair"]]])
    if not existing_chair_alert:
        models.execute_kw(db, uid, password, "quality.alert", "create", [{
            "name": "Wobbly Wheel - Office Chair",
            "product_id": chair_id,
            "description": "Customer reported wheel falls off.",
            "priority": "2"
        }])
        print("Created target alert.")
    
    # 4. Create Alert for Cabinet (The Distractor)
    existing_cab_alert = models.execute_kw(db, uid, password, "quality.alert", "search", 
        [[["name", "=", "Scratched Door - Cabinet"]]])
    if not existing_cab_alert and cabinet_id:
        models.execute_kw(db, uid, password, "quality.alert", "create", [{
            "name": "Scratched Door - Cabinet",
            "product_id": cabinet_id,
            "description": "Surface scratch on door.",
            "priority": "1"
        }])
        print("Created distractor alert.")

    # Save target product ID for export script to use later if needed
    with open("/tmp/target_product_id.txt", "w") as f:
        f.write(str(chair_id))

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Quality Alerts
# We navigate to the list view specifically
ensure_firefox "http://localhost:8069/web#action=quality_control.quality_alert_action_team&view_type=list"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="