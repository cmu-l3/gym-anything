#!/bin/bash
set -e

echo "=== Setting up update_qcp_to_measure task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# Create/ensure the target QCP exists with pass-fail type via RPC
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import time

ODOO_URL = "http://localhost:8069"
ODOO_DB = "odoo_quality"
ODOO_USER = "admin"
ODOO_PASSWORD = "admin"

QCP_NAME = "Dimensional Check - Cabinet with Doors"

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/common")
    uid = common.authenticate(ODOO_DB, ODOO_USER, ODOO_PASSWORD, {})
    if not uid:
        print("Failed to authenticate with Odoo", file=sys.stderr)
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/object")

    # 1. Get/Create product "Cabinet with Doors"
    product_ids = models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, "product.product", "search",
        [[["name", "ilike", "Cabinet with Doors"]]]
    )
    
    if not product_ids:
        # Create product template first
        tmpl_id = models.execute_kw(
            ODOO_DB, uid, ODOO_PASSWORD, "product.template", "create",
            [{"name": "Cabinet with Doors", "type": "product"}]
        )
        # Get variant
        product_ids = models.execute_kw(
            ODOO_DB, uid, ODOO_PASSWORD, "product.product", "search",
            [[["product_tmpl_id", "=", tmpl_id]]]
        )
    
    product_id = product_ids[0]
    print(f"Product 'Cabinet with Doors' id={product_id}")

    # 2. Get Receipts picking type (for context)
    picking_ids = models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, "stock.picking.type", "search",
        [[["code", "=", "incoming"]]]
    )
    picking_type_id = picking_ids[0] if picking_ids else None

    # 3. Check if our QCP already exists
    existing = models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "search_read",
        [[["name", "=", QCP_NAME]]],
        {"fields": ["id", "name", "test_type"], "limit": 1}
    )

    if existing:
        qcp_id = existing[0]["id"]
        print(f"QCP already exists: id={qcp_id}, resetting to passfail")
        # Reset to pass-fail (in case task was run before)
        models.execute_kw(
            ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "write",
            [[qcp_id], {
                "test_type": "passfail",
                "norm": 0.0,
                "tolerance_min": 0.0,
                "tolerance_max": 0.0,
            }]
        )
    else:
        # Create the QCP as pass-fail
        vals = {
            "name": QCP_NAME,
            "product_ids": [(6, 0, [product_id])],
            "test_type": "passfail",
            "title": QCP_NAME
        }
        if picking_type_id:
            vals["picking_type_ids"] = [(6, 0, [picking_type_id])]

        qcp_id = models.execute_kw(
            ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "create", [vals]
        )
        print(f"Created QCP: {QCP_NAME} id={qcp_id}")

    # 4. Record baseline for anti-gaming verification
    baseline = {
        "qcp_id": qcp_id,
        "qcp_name": QCP_NAME,
        "original_test_type": "passfail",
        "timestamp": time.time(),
    }
    with open("/tmp/task_baseline.json", "w") as f:
        json.dump(baseline, f)
    print(f"Baseline recorded: {json.dumps(baseline)}")

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Quality Control Points list
# We use the specific action ID if possible, or generic URL construction
ensure_firefox "http://localhost:8069/web#action=quality_control.quality_point_action&view_type=list"
sleep 5

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

# Verify capture
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Initial screenshot failed."
fi

echo "=== Task setup complete ==="