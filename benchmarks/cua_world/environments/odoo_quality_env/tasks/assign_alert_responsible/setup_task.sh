#!/bin/bash
# Do NOT use set -e before sourcing task_utils.sh
source /workspace/scripts/task_utils.sh
set -e

echo "=== Setting up task: assign_alert_responsible ==="

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create the specific quality alert for this task (no responsible assigned)
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import time
import json

ODOO_URL = "http://localhost:8069"
ODOO_DB = "odoo_quality"
ODOO_USER = "admin"
ODOO_PASSWORD = "admin"

ALERT_NAME = "Coating Peeling - Large Cabinet"

# Connect to Odoo
for attempt in range(10):
    try:
        common = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/common")
        uid = common.authenticate(ODOO_DB, ODOO_USER, ODOO_PASSWORD, {})
        models = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/object")
        break
    except Exception as e:
        print(f"Connection attempt {attempt+1} failed: {e}", file=sys.stderr)
        time.sleep(5)
else:
    print("ERROR: Could not connect to Odoo", file=sys.stderr)
    sys.exit(1)

# Check if alert already exists
existing = models.execute_kw(
    ODOO_DB, uid, ODOO_PASSWORD, "quality.alert", "search_read",
    [[["name", "=", ALERT_NAME]]],
    {"fields": ["id", "user_id"], "limit": 1}
)

if existing:
    # Reset: ensure user_id is cleared
    alert_id = existing[0]["id"]
    models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, "quality.alert", "write",
        [[alert_id], {"user_id": False}]
    )
    print(f"Reset existing alert id={alert_id}, cleared user_id")
else:
    # Find Large Cabinet product template
    products = models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, "product.template", "search_read",
        [[["name", "ilike", "Large Cabinet"]]],
        {"fields": ["id", "name"], "limit": 1}
    )
    product_tmpl_id = products[0]["id"] if products else False

    # Find product variant
    product_id = False
    if product_tmpl_id:
        variants = models.execute_kw(
            ODOO_DB, uid, ODOO_PASSWORD, "product.product", "search_read",
            [[["product_tmpl_id", "=", product_tmpl_id]]],
            {"fields": ["id"], "limit": 1}
        )
        product_id = variants[0]["id"] if variants else False

    # Get quality team
    teams = models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, "quality.alert.team", "search_read",
        [], {"fields": ["id"], "limit": 1}
    )
    team_id = teams[0]["id"] if teams else False

    # Get first (New) stage
    stages = models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, "quality.alert.stage", "search_read",
        [], {"fields": ["id", "name"], "limit": 1}
    )
    stage_id = stages[0]["id"] if stages else False

    vals = {
        "name": ALERT_NAME,
        "product_tmpl_id": product_tmpl_id,
        "product_id": product_id,
        "team_id": team_id,
        "stage_id": stage_id,
        "user_id": False,
        "priority": "0",
        "description": "Multiple Large Cabinet units received with coating peeling on the top surface. Supplier batch #LC-2024-0891. Affects approximately 12% of units in the last shipment.",
    }
    alert_id = models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, "quality.alert", "create", [vals]
    )
    print(f"Created alert '{ALERT_NAME}' with id={alert_id}")

# Record baseline counts for anti-gaming
alert_count = models.execute_kw(
    ODOO_DB, uid, ODOO_PASSWORD, "quality.alert", "search_count", [[]]
)

baseline = {
    "alert_count": alert_count,
    "timestamp": time.time()
}
with open("/tmp/task_baseline.json", "w") as f:
    json.dump(baseline, f)

PYTHON_EOF

# Launch Firefox and navigate to Quality Alerts list view
ensure_firefox "http://localhost:8069/web#action=quality_control.quality_alert_action_team&view_type=list"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="