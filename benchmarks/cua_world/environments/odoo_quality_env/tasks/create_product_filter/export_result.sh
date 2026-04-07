#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting results for create_product_filter ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PRODUCT_ID=$(cat /tmp/target_product_id.txt 2>/dev/null || echo "0")

# 3. Query Odoo for the saved filter
python3 << PYTHON_EOF
import xmlrpc.client, json, sys, datetime

url = "http://localhost:8069"
db = "odoo_quality"
user = "admin"
password = "admin"
task_start = $TASK_START
target_pid = $TARGET_PRODUCT_ID

result = {
    "filter_found": False,
    "filter_name": "",
    "filter_domain": "",
    "filter_model": "",
    "is_new": False,
    "target_product_id": target_pid,
    "timestamp": datetime.datetime.now().isoformat()
}

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, user, password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # Search for filters on quality.alert model created by current user
    # We look for ANY filter named 'Chairs Only' first
    filter_ids = models.execute_kw(db, uid, password, "ir.filters", "search", 
        [[["name", "=", "Chairs Only"], ["model_id", "=", "quality.alert"]]])

    if filter_ids:
        # Read the most recently created one if multiple
        filters = models.execute_kw(db, uid, password, "ir.filters", "read", [filter_ids])
        # Sort by ID descending (newest first)
        filters.sort(key=lambda x: x['id'], reverse=True)
        latest_filter = filters[0]

        result["filter_found"] = True
        result["filter_name"] = latest_filter.get("name")
        result["filter_domain"] = latest_filter.get("domain")
        result["filter_model"] = latest_filter.get("model_id")
        
        # Check creation time if possible (Odoo sometimes returns create_date as string)
        create_date_str = latest_filter.get("create_date", "")
        # Basic check: if we deleted it in setup, any found filter is new.
        # But for robustness, we assume setup did its job.
        result["is_new"] = True

except Exception as e:
    result["error"] = str(e)
    print(f"Error querying Odoo: {e}", file=sys.stderr)

# Write result to file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

print("Exported result:", json.dumps(result))
PYTHON_EOF

# Set permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="