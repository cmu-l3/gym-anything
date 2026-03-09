#!/bin/bash
echo "=== Exporting create_sales_quote results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# We use a Python script to interact with Manager.io via HTTP to verify the state.
# This avoids fragile UI scraping and uses the application's internal representation.
python3 -c '
import requests
import re
import json
import sys

BASE_URL = "http://localhost:8080"
TIMEOUT = 10
RESULT = {
    "module_enabled": False,
    "quote_found": False,
    "customer_match": False,
    "date_match": False,
    "expiry_match": False,
    "line_items_count": 0,
    "total_amount": 0.0,
    "line_items": [],
    "raw_html_snippet": ""
}

try:
    s = requests.Session()
    
    # 1. Login
    s.post(f"{BASE_URL}/login", data={"Username": "administrator"}, timeout=TIMEOUT)
    
    # 2. Get Business Key for Northwind
    biz_resp = s.get(f"{BASE_URL}/businesses", timeout=TIMEOUT)
    # Regex to find link like /start?FileID=... for Northwind
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_resp.text)
    if not m:
        m = re.search(r"start\?([^\"&\s]+)", biz_resp.text) # Fallback to first business
        
    if m:
        biz_key = m.group(1)
        # 3. Check if Sales Quotes module is enabled
        # We check if the link appears in the sidebar/menu of the main page
        main_page = s.get(f"{BASE_URL}/start?{biz_key}", timeout=TIMEOUT).text
        if "Sales Quotes" in main_page or "sales-quotes" in main_page:
            RESULT["module_enabled"] = True
            
            # 4. List Sales Quotes
            quotes_page = s.get(f"{BASE_URL}/sales-quotes?{biz_key}", timeout=TIMEOUT).text
            
            # Check for Alfreds Futterkiste in the list
            if "Alfreds Futterkiste" in quotes_page:
                RESULT["quote_found"] = True
                
                # Find the edit/view link for the quote
                # Typically /sales-quote-view?Key=...
                # We look for the row containing Alfreds Futterkiste
                # Simple parsing: find the link preceding the customer name in the table
                # Or find "View" button link
                q_match = re.search(r"sales-quote-view\?([^\"&\s]+)", quotes_page)
                if q_match:
                    quote_key = q_match.group(1)
                    detail_page = s.get(f"{BASE_URL}/sales-quote-view?{quote_key}", timeout=TIMEOUT).text
                    RESULT["raw_html_snippet"] = detail_page[:1000] # Debug info
                    
                    # Verify Customer
                    if "Alfreds Futterkiste" in detail_page:
                        RESULT["customer_match"] = True
                        
                    # Verify Dates (Format in Manager usually user-locale dependent, but often YYYY-MM-DD or DD/MM/YYYY)
                    # We check for presence of the specific strings
                    if "2025-06-15" in detail_page or "15/06/2025" in detail_page:
                        RESULT["date_match"] = True
                    if "2025-07-15" in detail_page or "15/07/2025" in detail_page:
                        RESULT["expiry_match"] = True
                        
                    # Verify Totals
                    # Look for 667.50
                    if "667.50" in detail_page:
                        RESULT["total_amount"] = 667.50
                        
                    # Extract Line Items (simplified scraping)
                    # We look for specific combinations of text
                    lines = []
                    if "Organic Chai Tea" in detail_page and "18.00" in detail_page:
                        lines.append({"desc": "Chai", "found": True})
                    if "Chang Mineral Water" in detail_page and "9.50" in detail_page:
                        lines.append({"desc": "Chang", "found": True})
                    if "Aniseed Syrup" in detail_page and "5.00" in detail_page:
                        lines.append({"desc": "Aniseed", "found": True})
                    
                    RESULT["line_items_count"] = len(lines)
                    RESULT["line_items"] = lines

except Exception as e:
    RESULT["error"] = str(e)

# Write result to file
with open("/tmp/task_result.json", "w") as f:
    json.dump(RESULT, f)
'

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="