#!/bin/bash
echo "=== Exporting record_investment_purchase results ==="

source /workspace/scripts/task_utils.sh

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_export_cookies.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Python script to query Manager.io state and generate JSON result
python3 -c "
import requests
import re
import json
import sys
import datetime

manager_url = '$MANAGER_URL'
cookie_file = '$COOKIE_FILE'
task_start_ts = $TASK_START

result = {
    'investments_enabled': False,
    'investment_item_found': False,
    'payment_found': False,
    'payment_details_correct': False,
    'data': {}
}

try:
    s = requests.Session()
    
    # Login
    s.post(f'{manager_url}/login', data={'Username': 'administrator'}, allow_redirects=True)
    
    # Get Business Key for Northwind
    biz_page = s.get(f'{manager_url}/businesses').text
    m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', biz_page)
    if not m:
        m = re.search(r'start\?([^\"&\s]+)', biz_page)
    
    if m:
        biz_key = m.group(1)
        # Navigate to business to set session context
        s.get(f'{manager_url}/start?{biz_key}')
        
        # 1. Check if Investments tab is enabled (visible in navigation)
        # We check the summary page or tabs page
        summary_page = s.get(f'{manager_url}/summary?{biz_key}').text
        if 'Investments' in summary_page and 'href=\"investments?' in summary_page:
            result['investments_enabled'] = True
            
        # 2. Check for Investment Item 'Northwind Strategic Fund'
        # We scrape the investments list page
        inv_page = s.get(f'{manager_url}/investments?{biz_key}').text
        if 'Northwind Strategic Fund' in inv_page:
            result['investment_item_found'] = True
            
        # 3. Check for Payment
        # We scrape the payments list page
        pay_page = s.get(f'{manager_url}/payments?{biz_key}').text
        
        # Look for the row with the amount and date
        # Simplify check: look for text occurrence of amount and date in the table
        # Note: 4,500.00 might be represented as 4,500.00 or 4500.00
        payment_found = False
        if '4,500.00' in pay_page or '4500.00' in pay_page:
             # Check date 15/08/2025 or 2025-08-15 depending on locale, 
             # usually Manager displays as '15 Aug 2025' or similar.
             # We look for loose match first
             if '15 Aug 2025' in pay_page or '2025-08-15' in pay_page or '15/08/2025' in pay_page:
                 payment_found = True
        
        result['payment_found'] = payment_found
        
        # Deep verify: Try to find the specific transaction ID and inspect it
        # Regex to find edit link for a payment row containing 4,500.00
        # Row usually contains date, description, amount, edit link
        # This is a heuristic check
        if payment_found and result['investment_item_found']:
             result['payment_details_correct'] = True

except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json