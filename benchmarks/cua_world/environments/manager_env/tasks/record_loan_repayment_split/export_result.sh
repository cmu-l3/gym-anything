#!/bin/bash
echo "=== Exporting record_loan_repayment_split results ==="

# Python script to scrape the current state from Manager.io
# This runs inside the container to access localhost:8080
cat > /tmp/inspect_manager_state.py << 'PYEOF'
import requests
import re
import json
import sys

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def login():
    """Login as administrator"""
    try:
        # First get the login page to set cookies
        r = SESSION.get(f"{BASE_URL}/login")
        # Post login
        r = SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
        return True
    except Exception as e:
        print(f"Login failed: {e}", file=sys.stderr)
        return False

def get_business_key():
    """Find Northwind Traders business key"""
    try:
        r = SESSION.get(f"{BASE_URL}/businesses")
        # Look for Northwind Traders link
        # Pattern: href="start?Key=..."
        # Context: "Northwind Traders"
        html = r.text
        # Regex to find the key for Northwind
        # It's usually /start?FileID=... or similar depending on version, 
        # but the task utils use a regex for 'start?([^"&\s]+)[^<]{0,300}Northwind Traders'
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', html)
        if not m:
             # Fallback to first business if Northwind specifically not found (unlikely)
             m = re.search(r'start\?([^"&\s]+)', html)
        
        if m:
            key = m.group(1)
            # Navigate to 'start' to initialize session for this business
            SESSION.get(f"{BASE_URL}/start?{key}")
            return key
    except Exception as e:
        print(f"Get business key failed: {e}", file=sys.stderr)
    return None

def check_chart_of_accounts(key):
    """Check if specific accounts exist"""
    accounts = {"Business Loan": False, "Loan Interest": False}
    try:
        # Manager.io usually lists accounts at /chart-of-accounts or via Settings
        # Since scraping the settings page tree is complex, we can also check /summary 
        # or just search the generic /chart-of-accounts endpoint if it exists.
        # Alternatively, we can check the 'account' dropdowns in forms, or the Summary page 
        # if the accounts have transactions.
        
        # Best bet: The Summary page lists accounts with balances. 
        # But newly created accounts with 0 balance might not show.
        # Let's try to fetch the Chart of Accounts page.
        r = SESSION.get(f"{BASE_URL}/chart-of-accounts?{key}")
        html = r.text
        
        for acc in accounts.keys():
            if acc in html:
                accounts[acc] = True
                
    except Exception as e:
        print(f"Check COA failed: {e}", file=sys.stderr)
    return accounts

def get_payments(key):
    """Get list of payments and details of the target payment"""
    payment_data = {
        "found": False,
        "date_match": False,
        "total_match": False,
        "split_correct": False,
        "lines": []
    }
    
    try:
        # List payments
        r = SESSION.get(f"{BASE_URL}/payments?{key}")
        html = r.text
        
        # We are looking for a payment of 1,250.00 on 15/02/2025 or 2025-02-15
        # The list view usually shows Date, Description, Amount.
        # Regex to find the View link for the target payment.
        # Looking for row containing 1,250.00 and date.
        
        # Simplified scraping: Find the View link for the most recent payment matching criteria
        # Pattern: <td ...>15/02/2025</td> ... <td ...>1,250.00</td> ... <a href="payment-view?Key=...">View</a>
        
        # Let's try to find the view link key.
        # Note: Date format might depend on locale, usually dd/mm/yyyy or yyyy-mm-dd.
        
        # We'll look for the specific amount "1,250.00"
        if "1,250.00" in html:
            payment_data["found"] = True
            payment_data["total_match"] = True
            
            # Extract the link to view this payment. 
            # We assume it's the one with 1,250.00.
            # Find the row
            # This is brittle regex, but Manager.io's HTML structure is relatively consistent.
            # We look for a link `payment-view?Key=...` near `1,250.00`
            
            # Find all view links
            view_links = re.findall(r'href="(payment-view\?[^"]+)"', html)
            
            # Iterate through payments to find the details
            for link in view_links:
                view_url = f"{BASE_URL}/{link}"
                r_view = SESSION.get(view_url)
                view_html = r_view.text
                
                # Check Date (15/02/2025 or 2025-02-15)
                if "15/02/2025" in view_html or "2025-02-15" in view_html or "Feb 15, 2025" in view_html:
                    payment_data["date_match"] = True
                    
                    # Check Lines
                    # We need 1000 to Business Loan and 250 to Loan Interest
                    # The view page lists lines.
                    
                    line_loan = False
                    line_interest = False
                    
                    # Check for "Business Loan" and "1,000.00" in close proximity (same row)
                    # We can count occurrences
                    if re.search(r'Business Loan.*1,000\.00', view_html, re.DOTALL) or \
                       re.search(r'1,000\.00.*Business Loan', view_html, re.DOTALL):
                        line_loan = True
                        payment_data["lines"].append({"account": "Business Loan", "amount": 1000})

                    if re.search(r'Loan Interest.*250\.00', view_html, re.DOTALL) or \
                       re.search(r'250\.00.*Loan Interest', view_html, re.DOTALL):
                        line_interest = True
                        payment_data["lines"].append({"account": "Loan Interest", "amount": 250})
                        
                    if line_loan and line_interest:
                        payment_data["split_correct"] = True
                        break # Found the correct payment

    except Exception as e:
        print(f"Get payments failed: {e}", file=sys.stderr)
        
    return payment_data

def main():
    if not login():
        print(json.dumps({"error": "Login failed"}))
        return

    key = get_business_key()
    if not key:
        print(json.dumps({"error": "Business key not found"}))
        return

    accounts_status = check_chart_of_accounts(key)
    payment_status = get_payments(key)

    result = {
        "accounts": accounts_status,
        "payment": payment_status,
        "business_key": key
    }
    
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
PYEOF

# Run the python script
echo "Running inspection script..."
python3 /tmp/inspect_manager_state.py > /tmp/manager_state.json

# Capture final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare final result JSON
# We combine the python inspection result with file timestamps/metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper to merge JSONs using python
cat > /tmp/merge_results.py << 'PYEOF'
import json
import sys
import os

try:
    with open('/tmp/manager_state.json', 'r') as f:
        state = json.load(f)
except:
    state = {}

final = {
    "state": state,
    "task_start": int(sys.argv[1]),
    "task_end": int(sys.argv[2]),
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": os.path.exists("/tmp/task_final.png")
}
print(json.dumps(final))
PYEOF

python3 /tmp/merge_results.py "$TASK_START" "$TASK_END" > /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="