#!/bin/bash
# Setup for change_qcp_product task
# NOTE: Do NOT use set -e before sourcing task_utils.sh
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: change_qcp_product ==="

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create/reset the target QCP with correct initial product using Python XML-RPC
python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, time

url = "http://localhost:8069"
db = "odoo_quality"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("ERROR: Could not authenticate", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # 1. Ensure "Acoustic Bloc Screens" product exists
    screen_tmpl_ids = models.execute_kw(db, uid, password, "product.template", "search",
        [[["name", "ilike", "Acoustic Bloc Screens"]]])
    if not screen_tmpl_ids:
        screen_tmpl_id = models.execute_kw(db, uid, password, "product.template", "create",
            [{"name": "Acoustic Bloc Screens", "type": "product"}])
    else:
        screen_tmpl_id = screen_tmpl_ids[0]

    screen_product_ids = models.execute_kw(db, uid, password, "product.product", "search",
        [[["product_tmpl_id", "=", screen_tmpl_id]]])
    screen_product_id = screen_product_ids[0]

    # 2. Ensure "Office Chair" product exists
    chair_tmpl_ids = models.execute_kw(db, uid, password, "product.template", "search",
        [[["name", "ilike", "Office Chair"]]])
    if not chair_tmpl_ids:
        chair_tmpl_id = models.execute_kw(db, uid, password, "product.template", "create",
            [{"name": "Office Chair", "type": "product"}])
    else:
        chair_tmpl_id = chair_tmpl_ids[0]

    chair_product_ids = models.execute_kw(db, uid, password, "product.product", "search",
        [[["product_tmpl_id", "=", chair_tmpl_id]]])
    chair_product_id = chair_product_ids[0]

    # 3. Determine quality.point field structure (product_ids vs product_tmpl_id)
    fields_info = models.execute_kw(db, uid, password, "quality.point", "fields_get",
        [["product_ids", "product_tmpl_id"]], {"attributes": ["type"]})
    
    product_field = "product_ids" if "product_ids" in fields_info else "product_tmpl_id"
    print(f"Using product field: {product_field}")

    # 4. Create or Reset the QCP
    qcp_name = "Visual Inspection - Incoming Screens"
    existing = models.execute_kw(db, uid, password, "quality.point", "search",
        [[["name", "=", qcp_name]]])

    vals = {
        "name": qcp_name,
        "test_type": "passfail",
        "title": qcp_name, # Title is sometimes used
    }

    # Set the OLD product (Acoustic Bloc Screens)
    if product_field == "product_ids":
        vals["product_ids"] = [(6, 0, [screen_product_id])]
    else:
        vals["product_tmpl_id"] = screen_tmpl_id

    if existing:
        qcp_id = existing[0]
        models.execute_kw(db, uid, password, "quality.point", "write", [[qcp_id], vals])
        print(f"Reset existing QCP id={qcp_id}")
    else:
        qcp_id = models.execute_kw(db, uid, password, "quality.point", "create", [vals])
        print(f"Created QCP id={qcp_id}")

    # 5. Save baseline for verification
    baseline = {
        "qcp_id": qcp_id,
        "qcp_name": qcp_name,
        "product_field": product_field,
        "screen_product_id": screen_product_id,
        "screen_tmpl_id": screen_tmpl_id,
        "chair_product_id": chair_product_id,
        "chair_tmpl_id": chair_tmpl_id,
        "timestamp": time.time(),
    }
    with open("/tmp/qcp_baseline.json", "w") as f:
        json.dump(baseline, f)

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Record global Odoo baseline
record_task_baseline "change_qcp_product"

# Launch Firefox and navigate to Quality Control Points
# This puts the agent in the right module but list view, so they have to search/find
ensure_firefox "http://localhost:8069/odoo/quality/control-points"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="