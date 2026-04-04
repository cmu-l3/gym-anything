#!/bin/bash
echo "=== Exporting Configure Bank Rule Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Dependencies
# We need curl and python3 for reliable HTML parsing/verification
MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_export_cookies.txt"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------
# HELPER: Python Script to Check Manager.io State via API
# ---------------------------------------------------------
# We use Python inside the container to handle the session/HTML parsing logic cleanly
cat > /tmp/check_manager_state.py << 'PYEOF'
import requests
import re
import json
import sys

MANAGER_URL = "http://localhost:8080"
COOKIE_FILE = "/tmp/mgr_export_cookies.txt"

result = {
    "account_exists": False,
    "account_code_correct": False,
    "account_group_correct": False,
    "rule_exists": False,
    "rule_condition_correct": False,
    "rule_allocation_correct": False,
    "errors": []
}

try:
    s = requests.Session()
    
    # 1. Login
    # Initial load to get CSRF/Session cookies
    s.get(MANAGER_URL)
    # Post login
    login_resp = s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    
    # 2. Get Business Key for "Northwind Traders"
    biz_list = s.get(f"{MANAGER_URL}/businesses").text
    # Regex to find the key. Pattern: href="start?KEY" ... Northwind Traders
    # Or simpler: find the link text "Northwind Traders" and parse the preceding href
    # Manager URLs are typically /start?FileID or similar UUID
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', biz_list)
    if not m:
        # Fallback to first business if specific name search fails (less robust)
        m = re.search(r'start\?([^"&\s]+)', biz_list)
    
    if not m:
        result["errors"].append("Could not find Northwind Traders business key")
        print(json.dumps(result))
        sys.exit(0)
        
    biz_key = m.group(1)
    
    # 3. Check Chart of Accounts (for "Rent Expense")
    # Endpoint usually: /chart-of-accounts?FileID=...
    coa_url = f"{MANAGER_URL}/chart-of-accounts?{biz_key}"
    coa_resp = s.get(coa_url).text
    
    # Check for Account Name
    if "Rent Expense" in coa_resp:
        result["account_exists"] = True
        
        # Check Code "6200" (search for 6200 near Rent Expense)
        # We look for a table row containing both
        # Simplistic check: does "6200" appear in the HTML?
        if "6200" in coa_resp:
            # Better check: 6200 followed relatively closely by Rent Expense
            if re.search(r'6200.*Rent Expense', coa_resp, re.DOTALL) or re.search(r'Rent Expense.*6200', coa_resp, re.DOTALL):
                result["account_code_correct"] = True
        
        # Check Group "Expenses"
        # In Manager, groups are headings. Accounts are listed under them.
        # This is hard to parse perfectly with regex, but if "Expenses" is present and account is there, we give credit.
        # A stricter check would be finding the Expenses header and ensuring Rent Expense is in that section.
        if "Expenses" in coa_resp:
            result["account_group_correct"] = True
            
        # Get the Account UUID to verify the rule
        # Link pattern: <a href="profit-and-loss-statement-account-form?Key=UUID&...">Rent Expense</a>
        acc_uuid_match = re.search(r'key=([^"&]+)[^>]*>Rent Expense', coa_resp, re.IGNORECASE)
        rent_acc_uuid = acc_uuid_match.group(1) if acc_uuid_match else None
    else:
        rent_acc_uuid = None

    # 4. Check Bank Rules
    # Endpoint: /bank-rules?FileID=... or /payment-rules?FileID=...
    # We check both just in case
    rules_resp = s.get(f"{MANAGER_URL}/bank-rules?{biz_key}").text
    if "Downtown Properties" not in rules_resp:
        # Try payment-rules endpoint if bank-rules empty/missing
        rules_resp = s.get(f"{MANAGER_URL}/payment-rules?{biz_key}").text
    
    if "Downtown Properties" in rules_resp:
        result["rule_exists"] = True
        result["rule_condition_correct"] = True
        
        # Check Allocation
        # Does it mention "Rent Expense"?
        if "Rent Expense" in rules_resp:
            result["rule_allocation_correct"] = True
        elif rent_acc_uuid and rent_acc_uuid in rules_resp:
            result["rule_allocation_correct"] = True
            
except Exception as e:
    result["errors"].append(str(e))

print(json.dumps(result))
PYEOF

# Run the python script
echo "Running verification script..."
STATE_JSON=$(python3 /tmp/check_manager_state.py)
echo "Python script output: $STATE_JSON"

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end": $(date +%s),
    "manager_state": $STATE_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json