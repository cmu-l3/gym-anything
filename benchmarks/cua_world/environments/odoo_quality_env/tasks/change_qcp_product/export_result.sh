#!/bin/bash
# Export script for change_qcp_product task
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to inspect database state
python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, os

url = "http://localhost:8069"
db = "odoo_quality"
username = "admin"
password = "admin"
output_file = "/tmp/task_result.json"

result = {
    "qcp_exists": False,
    "correct_product_associated": False,
    "old_product_removed": False,
    "name_unchanged": False,
    "test_type_unchanged": False,
    "error": None
}

try:
    # Load baseline
    if not os.path.exists("/tmp/qcp_baseline.json"):
        raise Exception("Baseline file missing")
        
    with open("/tmp/qcp_baseline.json") as f:
        baseline = json.load(f)

    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    qcp_id = baseline["qcp_id"]
    product_field = baseline["product_field"]
    
    # Check if record still exists
    # We check by ID to ensure they edited the existing one, not created a new one
    qcp_data = models.execute_kw(db, uid, password, "quality.point", "read", 
        [[qcp_id], ["name", "test_type", product_field]])
    
    if not qcp_data:
        # Check if they recreated it (partial credit logic in verifier)
        # But for export, we just note it's gone
        result["qcp_exists"] = False
    else:
        qcp = qcp_data[0]
        result["qcp_exists"] = True
        
        # Check Name
        # Handle Odoo 17 JSONB names (e.g. {'en_US': 'Name'})
        current_name = qcp.get("name")
        if isinstance(current_name, dict):
            current_name = current_name.get("en_US", str(current_name))
        result["name_unchanged"] = (str(current_name) == baseline["qcp_name"])
        
        # Check Test Type
        result["test_type_unchanged"] = (qcp.get("test_type") == "passfail")
        
        # Check Product
        # Logic depends on whether it's Many2many (list of IDs) or Many2one (ID, Name tuple)
        current_products = qcp.get(product_field)
        if not current_products:
            current_products = []
        
        # Normalize to list of IDs
        current_ids = []
        if isinstance(current_products, list) and len(current_products) > 0 and isinstance(current_products[0], int):
             # Many2many list of ints
             current_ids = current_products
        elif isinstance(current_products, (list, tuple)) and len(current_products) > 0 and isinstance(current_products[0], int):
             # Many2one tuple (id, name)
             current_ids = [current_products[0]]
        elif isinstance(current_products, int):
             current_ids = [current_products]

        # Targets
        target_chair_id = baseline["chair_product_id"] if product_field == "product_ids" else baseline["chair_tmpl_id"]
        old_screen_id = baseline["screen_product_id"] if product_field == "product_ids" else baseline["screen_tmpl_id"]
        
        result["correct_product_associated"] = (target_chair_id in current_ids)
        result["old_product_removed"] = (old_screen_id not in current_ids)
        
        # Debug info
        result["debug"] = {
            "current_ids": current_ids,
            "target_chair": target_chair_id,
            "old_screen": old_screen_id,
            "field": product_field
        }

except Exception as e:
    result["error"] = str(e)

with open(output_file, "w") as f:
    json.dump(result, f)
PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="