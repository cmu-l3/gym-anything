#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Export database state to JSON using Python
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import time

ODOO_URL = "http://localhost:8069"
ODOO_DB = "odoo_quality"
ODOO_USER = "admin"
ODOO_PASSWORD = "admin"
ALERT_NAME = "Coating Peeling - Large Cabinet"

try:
    # Connect
    common = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/common")
    uid = common.authenticate(ODOO_DB, ODOO_USER, ODOO_PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/object")

    # Get the specific alert
    alerts = models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, "quality.alert", "search_read",
        [[["name", "=", ALERT_NAME]]],
        {"fields": ["id", "user_id", "write_date", "create_date"]}
    )

    alert_data = alerts[0] if alerts else None

    # Get total alert count (for anti-gaming)
    current_alert_count = models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, "quality.alert", "search_count", [[]]
    )

    # Read baseline if available
    baseline_count = -1
    try:
        with open("/tmp/task_baseline.json", "r") as f:
            baseline = json.load(f)
            baseline_count = baseline.get("alert_count", -1)
    except:
        pass

    result = {
        "alert_found": bool(alert_data),
        "alert_data": alert_data,
        "current_alert_count": current_alert_count,
        "baseline_alert_count": baseline_count,
        "timestamp": time.time()
    }

    # Save to temp file first
    with open("/tmp/task_result_temp.json", "w") as f:
        json.dump(result, f)

except Exception as e:
    error_result = {"error": str(e), "alert_found": False}
    with open("/tmp/task_result_temp.json", "w") as f:
        json.dump(error_result, f)
PYTHON_EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"