#!/bin/bash
# Setup for duplicate_qcp_for_product task
# Creates the source QCP and records baseline state

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up duplicate_qcp_for_product task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is responsive
echo "Waiting for Odoo to be ready..."
for i in {1..30}; do
    if curl -s "http://localhost:8069/web/health" > /dev/null; then
        echo "Odoo is responsive"
        break
    fi
    sleep 2
done

# Run Python setup script to create data and record baseline
python3 << 'PYEOF'
import xmlrpc.client
import json
import time
import sys

ODOO_URL = "http://localhost:8069"
ODOO_DB = "odoo_quality"
ODOO_USER = "admin"
ODOO_PASSWORD = "admin"

try:
    common = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/common")
    uid = common.authenticate(ODOO_DB, ODOO_USER, ODOO_PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/object")
    print(f"Connected as uid={uid}")

    # --- Ensure "Large Cabinet" product exists ---
    large_cab_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "product.template", "search",
        [[["name", "ilike", "Large Cabinet"]]])
    if not large_cab_ids:
        large_cab_id = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "product.template", "create",
            [{"name": "Large Cabinet", "type": "product", "sale_ok": True, "purchase_ok": True}])
        print(f"Created Large Cabinet product template id={large_cab_id}")
    else:
        large_cab_id = large_cab_ids[0]
        print(f"Found Large Cabinet product template id={large_cab_id}")

    # Get Large Cabinet variant
    large_cab_variant_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "product.product", "search",
        [[["product_tmpl_id", "=", large_cab_id]]])
    large_cab_variant_id = large_cab_variant_ids[0] if large_cab_variant_ids else None

    # --- Ensure "Cabinet with Doors" product exists ---
    cab_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "product.template", "search",
        [[["name", "ilike", "Cabinet with Doors"]]])
    if not cab_ids:
        cab_id = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "product.template", "create",
            [{"name": "Cabinet with Doors", "type": "product", "sale_ok": True, "purchase_ok": True}])
        print(f"Created Cabinet with Doors product template id={cab_id}")
    else:
        cab_id = cab_ids[0]
        print(f"Found Cabinet with Doors product template id={cab_id}")

    cab_variant_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "product.product", "search",
        [[["product_tmpl_id", "=", cab_id]]])
    cab_variant_id = cab_variant_ids[0] if cab_variant_ids else None

    # --- Get Receipts picking type ---
    receipts_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "stock.picking.type", "search",
        [[["code", "=", "incoming"]]])
    receipts_id = receipts_ids[0] if receipts_ids else None

    # --- Get or create quality team ---
    team_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "quality.alert.team", "search", [[]])
    team_id = team_ids[0] if team_ids else None

    # --- Delete existing QCP with our specific name (idempotent) ---
    existing_source = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "search",
        [[["name", "ilike", "Surface Quality Check - Cabinet with Doors"]]])
    if existing_source:
        models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "unlink", [existing_source])
        print(f"Deleted {len(existing_source)} existing source QCP(s)")

    # Also clean up any leftover target QCPs from previous runs
    existing_target = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "search",
        [[["name", "ilike", "Surface Quality Check - Large Cabinet"]]])
    if existing_target:
        models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "unlink", [existing_target])
        print(f"Deleted {len(existing_target)} existing target QCP(s)")

    # --- Create the source QCP ---
    qcp_vals = {
        "name": "Surface Quality Check - Cabinet with Doors",
        "title": "Surface Quality Check - Cabinet with Doors",
        "test_type": "passfail",
        "note": "<p>Inspect all exterior surfaces for scratches, dents, and finish defects. Check that doors open/close smoothly and hinges are properly aligned. Verify color consistency matches production sample.</p>",
    }

    if cab_variant_id:
        qcp_vals["product_ids"] = [(6, 0, [cab_variant_id])]
    if receipts_id:
        qcp_vals["picking_type_ids"] = [(6, 0, [receipts_id])]
    if team_id:
        qcp_vals["team_id"] = team_id

    source_qcp_id = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "create", [qcp_vals])
    print(f"Created source QCP: 'Surface Quality Check - Cabinet with Doors' id={source_qcp_id}")

    # --- Record baseline ---
    qcp_count = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "search_count", [[]])
    print(f"Baseline QCP count: {qcp_count}")

    baseline = {
        "timestamp": time.time(),
        "qcp_count": qcp_count,
        "source_qcp_id": source_qcp_id,
        "large_cab_template_id": large_cab_id,
        "large_cab_variant_id": large_cab_variant_id,
        "cab_template_id": cab_id,
        "cab_variant_id": cab_variant_id,
        "team_id": team_id,
    }

    with open("/tmp/duplicate_qcp_baseline.json", "w") as f:
        json.dump(baseline, f)

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Launch Firefox and navigate to QCP list
echo "Launching Firefox at Quality Control Points list..."
ensure_firefox "http://localhost:8069/web#action=quality_control.quality_point_action"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="