#!/bin/bash
echo "=== Exporting process_expense_claim result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract Data from Manager.io using Python
# We need to verify:
# 1. Expense Claims module is enabled
# 2. Payer "Nancy Davolio" exists
# 3. Claim for 125.50 exists

python3 - <<EOF
import requests
import re
import json
import sys

result = {
    "module_enabled": False,
    "payer_exists": False,
    "claim_exists": False,
    "claim_amount_correct": False,
    "claim_description_match": False,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}

base_url = "http://localhost:8080"
s = requests.Session()

try:
    # Login
    s.post(base_url + "/login", data={"Username": "administrator"}, timeout=5)
    
    # Get Business Key
    r = s.get(base_url + "/businesses", timeout=5)
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', r.text)
        
    if m:
        key = m.group(1)
        
        # 1. Check if Module is Enabled (Sidebar check)
        # We fetch the summary page and look for the link
        r_summary = s.get(f"{base_url}/summary?{key}", timeout=5)
        if "expense-claims?" in r_summary.text:
            result["module_enabled"] = True
            
        # 2. Check Payer
        r_payers = s.get(f"{base_url}/expense-claim-payers?{key}", timeout=5)
        if "Nancy Davolio" in r_payers.text:
            result["payer_exists"] = True
            
        # 3. Check Claim
        r_claims = s.get(f"{base_url}/expense-claims?{key}", timeout=5)
        if "Nancy Davolio" in r_claims.text:
            result["claim_exists"] = True
            
            # Check amount (125.50)
            if "125.50" in r_claims.text:
                result["claim_amount_correct"] = True
                
            # Check description keywords
            lower_text = r_claims.text.lower()
            if "dinner" in lower_text or "expo" in lower_text:
                result["claim_description_match"] = True

except Exception as e:
    result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="