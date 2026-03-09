#!/bin/bash
echo "=== Exporting add_expense_accounts result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to scrape the final Chart of Accounts state
# This runs inside the container where it has access to localhost:8080
cat << 'EOF' > /tmp/scrape_results.py
import requests
import re
import json
import sys
import os

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def get_business_key():
    # Login
    SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"})
    # Get businesses page
    resp = SESSION.get(f"{BASE_URL}/businesses")
    # Find Northwind
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if not m:
        # Fallback to any business
        m = re.search(r'start\?([^"&\s]+)', resp.text)
    return m.group(1) if m else None

def get_chart_of_accounts_data(key):
    url = f"{BASE_URL}/chart-of-accounts?{key}"
    print(f"Fetching {url}...")
    resp = SESSION.get(url)
    if resp.status_code != 200:
        print(f"Failed to fetch Chart of Accounts: {resp.status_code}")
        return "", []
    
    html = resp.text
    
    # We need to extract rows that look like accounts.
    # Manager.io tables typically have rows <tr> with cells <td>.
    # We are looking for rows containing our expected codes (5100, 5200, 5300).
    
    found_accounts = []
    
    # Regex to find a row and capture its cell contents roughly
    # This is a heuristic parser since we don't have BeautifulSoup
    # We look for patterns like: <td>Code</td> ... <td>Name</td>
    
    # Split by rows
    rows = html.split('</tr>')
    for row in rows:
        # Clean up tags
        text_content = re.sub(r'<[^>]+>', ' ', row).strip()
        # Normalize spaces
        text_content = re.sub(r'\s+', ' ', text_content)
        
        # Check if this row contains any of our target data
        # We store the raw text content for the verifier to fuzzy match
        if text_content:
            found_accounts.append(text_content)
            
    return html, found_accounts

def main():
    try:
        key = get_business_key()
        if not key:
            print("Business key not found")
            return

        html, accounts_text = get_chart_of_accounts_data(key)
        
        # Also try to read initial state
        initial_accounts = []
        if os.path.exists("/tmp/initial_accounts.json"):
            with open("/tmp/initial_accounts.json", "r") as f:
                initial_accounts = json.load(f)

        result = {
            "business_key": key,
            "final_accounts_text_rows": accounts_text,
            "initial_accounts_raw": initial_accounts,
            "html_snapshot_length": len(html),
            # Check specifically for our expected codes in the raw HTML for a boolean signal
            "found_5100": "5100" in html,
            "found_5200": "5200" in html,
            "found_5300": "5300" in html,
            "found_Freight": "Freight and Delivery" in html,
            "found_Vehicle": "Vehicle Maintenance" in html,
            "found_Professional": "Professional Services" in html,
            "found_Expenses_Group": "Expenses" in html
        }
        
        with open("/tmp/task_result.json", "w") as f:
            json.dump(result, f, indent=2)
            
        print("Scraping complete.")
        
    except Exception as e:
        print(f"Error scraping results: {e}")
        # Write basic error result
        with open("/tmp/task_result.json", "w") as f:
            json.dump({"error": str(e)}, f)

if __name__ == "__main__":
    main()
EOF

python3 /tmp/scrape_results.py

# Add timestamps to the result
if [ -f /tmp/task_result.json ]; then
    # Use jq to add fields if available, otherwise simple string append (risky) or python
    python3 -c "import json; d=json.load(open('/tmp/task_result.json')); d['task_start']=$TASK_START; d['task_end']=$TASK_END; d['screenshot_path']='/tmp/task_final.png'; json.dump(d, open('/tmp/task_result.json','w'))"
fi

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json