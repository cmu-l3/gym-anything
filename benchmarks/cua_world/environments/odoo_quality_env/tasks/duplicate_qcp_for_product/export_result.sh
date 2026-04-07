#!/bin/bash
# Export results for duplicate_qcp_for_product task

source /workspace/scripts/task_utils.sh

echo "=== Exporting duplicate_qcp_for_product result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query current state and merge with baseline
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os
import time

ODOO_URL = "http://localhost:8069"
ODOO_DB = "odoo_quality"
ODOO_USER = "admin"
ODOO_PASSWORD = "admin"
BASELINE_FILE = "/tmp/duplicate_qcp_baseline.json"
RESULT_FILE = "/tmp/task_result.json"

def normalize_name(name):
    if isinstance(name, dict):
        return name.get("en_US", str(name)).strip()
    return str(name).strip()

try:
    # Load baseline
    baseline = {}
    if os.path.exists(BASELINE_FILE):
        with open(BASELINE_FILE) as f:
            baseline = json.load(f)

    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/common")
    uid = common.authenticate(ODOO_DB, ODOO_USER, ODOO_PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/object")

    # Get current QCP count
    current_count = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "search_count", [[]])

    # Search for the new QCP
    target_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "search",
        [[["name", "ilike", "Surface Quality Check - Large Cabinet"]]])
    
    new_qcp_data = []
    if target_ids:
        new_qcp_data = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "read",
            [target_ids, ["id", "name", "test_type", "product_ids", "team_id", "create_date", "picking_type_ids"]])
        
        # Resolve product names for verification
        for qcp in new_qcp_data:
            if qcp.get("product_ids"):
                prods = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "product.product", "read",
                    [qcp["product_ids"], ["name"]])
                qcp["product_names"] = [normalize_name(p["name"]) for p in prods]

    # Check source QCP state
    source_qcp_data = {}
    source_id = baseline.get("source_qcp_id")
    if source_id:
        source_data = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "read",
            [[source_id], ["id", "name", "product_ids", "test_type", "active"]])
        if source_data:
            source_qcp_data = source_data[0]
            if source_qcp_data.get("product_ids"):
                prods = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, "product.product", "read",
                    [source_qcp_data["product_ids"], ["name"]])
                source_qcp_data["product_names"] = [normalize_name(p["name"]) for p in prods]

    # Construct result object
    result = {
        "timestamp": time.time(),
        "baseline": baseline,
        "current_state": {
            "qcp_count": current_count,
            "new_qcps": new_qcp_data,
            "source_qcp": source_qcp_data
        }
    }

    # Save to file with proper permissions
    with open(RESULT_FILE, "w") as f:
        json.dump(result, f, indent=2)

    # Ensure readable by ga/others
    os.chmod(RESULT_FILE, 0o666)
    print("Export successful")

except Exception as e:
    print(f"Export failed: {e}", file=sys.stderr)
    # Write error JSON
    with open(RESULT_FILE, "w") as f:
        json.dump({"error": str(e)}, f)
PYEOF

echo "=== Export complete ==="