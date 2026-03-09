#!/bin/bash
set -e

echo "=== Exporting Enforce Credit Limit results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Retrieve timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# We need to query the current state of the customers to verify
# We'll use a Python script to fetch the details via API and dump to JSON
cat > /tmp/fetch_results.py << 'EOF'
import requests
import re
import json
import sys

MANAGER_URL = "http://localhost:8080"
SESSION = requests.Session()

def login():
    SESSION.post(f"{MANAGER_URL}/login", data={"Username": "administrator"})

def get_business_key():
    r = SESSION.get(f"{MANAGER_URL}/businesses")
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', r.text)
    return m.group(1) if m else None

def get_customer_data(biz_key, name):
    # Find customer key
    r = SESSION.get(f"{MANAGER_URL}/customers?{biz_key}")
    
    # Scan lines to find key associated with name
    lines = r.text.split('\n')
    key = None
    curr_key = None
    for line in lines:
        m_key = re.search(r'customer-form\?Key=([a-f0-9-]+)', line)
        if m_key:
            curr_key = m_key.group(1)
        if name in line and curr_key:
            key = curr_key
            break
            
    if not key:
        return None
        
    # Get form data
    r_form = SESSION.get(f"{MANAGER_URL}/customer-form?Key={key}&{biz_key}")
    
    # Extract JSON value from hidden input
    # value="{&quot;Name&quot;:&quot;...&quot;}"
    m_val = re.search(r'value="(\{.*?\})"', r_form.text)
    if m_val:
        # Unescape HTML entities
        json_str = m_val.group(1).replace('&quot;', '"').replace('&amp;', '&')
        try:
            return json.loads(json_str)
        except:
            return None
    return None

def main():
    try:
        login()
        biz_key = get_business_key()
        if not biz_key:
            print(json.dumps({"error": "Business not found"}))
            return

        customers = {}
        for name in ["Stop-N-Shop", "Save-a-Lot Markets", "Quick-Stop Groceries"]:
            data = get_customer_data(biz_key, name)
            if data:
                customers[name] = {
                    "CreditLimit": data.get("CreditLimit"),
                    "Name": data.get("Name")
                }
            else:
                customers[name] = None
                
        result = {
            "customers": customers,
            "success": True
        }
        print(json.dumps(result, indent=2))
        
    except Exception as e:
        print(json.dumps({"error": str(e), "success": False}))

if __name__ == "__main__":
    main()
EOF

# Run fetch script and save to file
python3 /tmp/fetch_results.py > /tmp/customer_state.json

# Construct final result JSON
# We combine the customer state with timestamps
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "customer_state": $(cat /tmp/customer_state.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard result location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="