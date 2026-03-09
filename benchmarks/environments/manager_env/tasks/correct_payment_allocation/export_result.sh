#!/bin/bash
echo "=== Exporting correct_payment_allocation results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to fetch the current state of the specific payment
cat > /tmp/export_state.py << 'EOF'
import requests
import json
import sys
import re

MANAGER_URL = "http://localhost:8080"

def main():
    try:
        with open("/tmp/task_metadata.json", "r") as f:
            meta = json.load(f)
    except FileNotFoundError:
        print("Metadata not found")
        sys.exit(1)
        
    biz_key = meta.get("business_key")
    payment_uuid = meta.get("payment_uuid")
    
    if not biz_key or not payment_uuid:
        print("Missing keys in metadata")
        sys.exit(1)
        
    # Login
    s = requests.Session()
    s.post(MANAGER_URL + "/login", data={"Username": "administrator"})
    
    # Fetch the payment view page
    # In Manager, the "view" page is HTML. 
    # To get the JSON data, we usually need to pretend to "Edit" it to get the form data.
    edit_url = f"{MANAGER_URL}/payment-form?Key={payment_uuid}&{biz_key}" # URL pattern for edit
    
    r = s.get(edit_url)
    
    # Extract the JSON blob from the input value
    # <input type="hidden" name="..." value="{JSON}" />
    # The name is a UUID.
    m = re.search(r'name="[a-f0-9-]{36}" value="({.*?})"', r.text)
    
    payment_data = {}
    if m:
        try:
            # HTML entities might need unescaping if present, but usually value="{...}" is clean or basic escaped
            json_str = m.group(1).replace("&quot;", '"')
            payment_data = json.loads(json_str)
        except Exception as e:
            print(f"JSON parse error: {e}")
            
    # Also get the account UUIDs to map names back if possible
    # (We rely on verifier to check UUIDs against the ones we saved in metadata)
    
    result = {
        "payment_uuid": payment_uuid,
        "payment_exists": bool(m),
        "data": payment_data,
        "metadata_ref": meta,
        "task_end_time": int(re.sub(r'\..*', '', str(sys.time()))) if 'sys' in locals() else 0
    }
    
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f, indent=2)

if __name__ == "__main__":
    main()
EOF

python3 /tmp/export_state.py

# Add basic shell-based checks for redundancy
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")
echo "App running: $APP_RUNNING"

# If python script failed to create json, create a fallback
if [ ! -f /tmp/task_result.json ]; then
    echo "{\"error\": \"Export script failed\"}" > /tmp/task_result.json
fi

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="