#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

COOKIE_FILE="/tmp/mgr_cookies.txt"
MANAGER_URL="http://localhost:8080"
BIZ_KEY=$(cat /tmp/biz_key.txt 2>/dev/null)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Python script to scrape final state
python3 - <<PYEOF > /tmp/scrape_results.json
import requests
import re
import json
import sys

s = requests.Session()
url = "$MANAGER_URL"
biz_key = "$BIZ_KEY"

# Authenticate (reuse session/cookies if possible, or re-login)
s.post(f"{url}/login", data={"Username": "administrator"})

results = {
    "invoice_paid": False,
    "invoice_balance": 1000.0,
    "cash_increase": 0.0,
    "tax_asset_increase": 0.0,
    "receipt_exists": False
}

try:
    # 1. Check Invoice Status
    # Fetch Sales Invoices list
    r = s.get(f"{url}/sales-invoices?{biz_key}")
    # Look for INV-CONS-001 row. The structure is complex, but usually 'Balance due' is in a column.
    # We'll parse the text loosely.
    if "INV-CONS-001" in r.text:
        # Simple heuristic: Split by invoice ref, look at next few numbers
        # Better: Load the specific invoice view if possible, but we don't know its Key.
        # We'll assume if "INV-CONS-001" is followed by "0.00" in the balance column (last col usually).
        # Or look for "Paid in full" badge if visible in HTML.
        
        # Regex to find the row for INV-CONS-001
        # Row usually contains: Date, Ref, Customer, Desc, Amount, Balance
        # We look for INV-CONS-001 ... then a balance.
        # This is brittle. Let's try to find the invoice key from the list.
        inv_match = re.search(r'sales-invoice-view\?Key=([^"]+)">INV-CONS-001', r.text)
        if inv_match:
            inv_key = inv_match.group(1)
            # Get invoice view
            r_inv = s.get(f"{url}/sales-invoice-view?Key={inv_key}&{biz_key}")
            
            # Check for Balance Due text
            # Usually "Balance due ... 0.00"
            if "Balance due" in r_inv.text and "0.00" in r_inv.text:
                 results["invoice_balance"] = 0.0
                 results["invoice_paid"] = True
            elif "Paid in full" in r_inv.text: # Often a stamp
                 results["invoice_balance"] = 0.0
                 results["invoice_paid"] = True
            else:
                 # Try to extract number
                 m = re.search(r'Balance due.*?([\d,]+\.\d{2})', r_inv.text, re.DOTALL)
                 if m:
                     results["invoice_balance"] = float(m.group(1).replace(',', ''))

    # 2. Check Account Balances (Summary Page)
    r_sum = s.get(f"{url}/summary?{biz_key}")
    
    # Parse "Cash on Hand"
    # Find "Cash on Hand" link, then the amount inside the tag
    # <td class="text-right"><a href="...">1,234.56</a></td>
    
    def get_balance(html, account_name):
        # Very rough regex for summary table structure
        # Account Name ... Amount
        # Escape special chars in account name
        acc = re.escape(account_name)
        # Regex: AccountName <...stuff...> >Amount<
        # This is tricky without BS4. We'll try to find the specific link text.
        try:
            # Locate the account name
            idx = html.find(account_name)
            if idx == -1: return 0.0
            # Look forward for the number
            snippet = html[idx:idx+1000]
            # Match number: 1,234.56 or (100.00)
            matches = re.findall(r'>([0-9,]+\.[0-9]{2})<', snippet)
            if matches:
                # The first number after the name in Summary is usually the balance
                return float(matches[0].replace(',', ''))
            return 0.0
        except:
            return 0.0

    current_cash = get_balance(r_sum.text, "Cash on Hand")
    current_tax = get_balance(r_sum.text, "Withholding Tax Receivable")
    
    # Get initial cash
    try:
        with open('/tmp/initial_cash.txt', 'r') as f:
            initial_cash = float(f.read().strip())
    except:
        initial_cash = 0.0
        
    results["cash_increase"] = current_cash - initial_cash
    results["tax_asset_increase"] = current_tax  # Assuming started at 0

except Exception as e:
    results["error"] = str(e)

print(json.dumps(results))
PYEOF

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
SCRAPED_DATA=$(cat /tmp/scrape_results.json)
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scraped_data": $SCRAPED_DATA,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="