#!/bin/bash
echo "=== Exporting Consolidate Inventory Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# We need to query the current state of the entities recorded in setup
cat > /tmp/check_state.py << 'EOF'
import requests
import json
import re
import os
import sys

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def check_task():
    try:
        if not os.path.exists("/tmp/task_ids.json"):
            return {"error": "Setup data missing"}
            
        with open("/tmp/task_ids.json", "r") as f:
            ids = json.load(f)
            
        key = ids["business_key"]
        dup_uuid = ids["duplicate_item_uuid"]
        master_uuid = ids["master_item_uuid"]
        si_key = ids["sales_invoice_key"]
        pi_key = ids["purchase_invoice_key"]
        
        # Login
        SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
        # Set context
        SESSION.get(f"{BASE_URL}/start?{key}")

        # 1. Check if Duplicate Item still exists
        # We try to access its form. If it's deleted, it might return 404 or redirect to list
        dup_resp = SESSION.get(f"{BASE_URL}/inventory-item-form?Key={dup_uuid}&{key}")
        
        # In Manager, deleted items often just disappear or the link invalidates
        # If the form loads and contains the name, it exists.
        duplicate_exists = "Aniseed Syrup (Old)" in dup_resp.text
        
        # 2. Check Sales Invoice Line Item
        si_resp = SESSION.get(f"{BASE_URL}/sales-invoice-form?Key={si_key}&{key}")
        # We look for the JSON data embedded in the value="{...}"
        si_match = re.search(r'value="({.*})"', si_resp.text)
        si_item_uuid = None
        if si_match:
            try:
                # The HTML attribute is escaped, might need unescaping but simple JSON often works
                # However, Manager often HTML-encodes quotes in the value attribute.
                # A safer check is to see if the Master UUID is present in the response text 
                # and the Duplicate UUID is NOT.
                pass
            except:
                pass
        
        # Robust string check on the invoice form
        # Does it contain the Master UUID?
        si_uses_master = master_uuid in si_resp.text
        si_uses_duplicate = dup_uuid in si_resp.text
        
        # 3. Check Purchase Invoice
        pi_resp = SESSION.get(f"{BASE_URL}/purchase-invoice-form?Key={pi_key}&{key}")
        pi_uses_master = master_uuid in pi_resp.text
        pi_uses_duplicate = dup_uuid in pi_resp.text
        
        # 4. Check Master Item Qty
        # We need to parse the inventory list for "Aniseed Syrup"
        inv_resp = SESSION.get(f"{BASE_URL}/inventory-items?{key}")
        # This is harder to parse precisely without clean API, but we can assume
        # if the transactions are moved, the qty is moved.
        # We will rely on the transaction links.
        
        return {
            "duplicate_item_exists": duplicate_exists,
            "sales_invoice_corrected": (si_uses_master and not si_uses_duplicate),
            "purchase_invoice_corrected": (pi_uses_master and not pi_uses_duplicate),
            "ids_debug": ids
        }
        
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    result = check_task()
    with open("/tmp/py_result.json", "w") as f:
        json.dump(result, f)
EOF

python3 /tmp/check_state.py

# Combine info
CHECK_RESULT=$(cat /tmp/py_result.json)
APP_RUNNING=$(pgrep -f "Firefox" > /dev/null && echo "true" || echo "false")
OUTPUT_EXISTS="true" 

# Create final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "check_state": $CHECK_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
echo "Export complete."
cat /tmp/task_result.json