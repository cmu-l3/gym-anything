#!/bin/bash
# Export script for create_sales_order task
# Scrapes Manager.io API/HTML to verify:
# 1. Sales Orders tab is enabled
# 2. Specific Sales Order exists with correct data

echo "=== Exporting create_sales_order results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to scrape the local Manager instance
# We use the installed python3-requests package
python3 -c '
import requests
import json
import re
import sys

MANAGER_URL = "http://localhost:8080"
RESULT = {
    "module_enabled": False,
    "order_found": False,
    "order_details": {},
    "error": None
}

try:
    s = requests.Session()
    
    # 1. Login
    login_resp = s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    
    # 2. Get Northwind Business Key
    biz_page = s.get(f"{MANAGER_URL}/businesses").text
    # Regex to find the key for "Northwind Traders"
    # Matches: start?Key=XXXX-XXXX-XXXX-XXXX">Northwind Traders
    # or just looks for the first business if specific name match fails (fallback)
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
    if not m:
        m = re.search(r"start\?([^\"&\s]+)", biz_page)
    
    if not m:
        RESULT["error"] = "Could not find Business Key"
    else:
        biz_key = m.group(1)
        
        # 3. Check if Sales Orders tab is enabled
        # We check the dashboard/summary page or the tabs customization page
        # If enabled, the link to /sales-orders?Key=... will exist in the sidebar
        summary_page = s.get(f"{MANAGER_URL}/summary?{biz_key}").text
        
        # Check for sidebar link
        if f"/sales-orders?{biz_key}" in summary_page:
            RESULT["module_enabled"] = True
            
            # 4. Search for the Sales Order
            # Get the Sales Orders list page
            so_list_page = s.get(f"{MANAGER_URL}/sales-orders?{biz_key}").text
            
            # Look for the reference "SO-90210"
            if "SO-90210" in so_list_page:
                RESULT["order_found"] = True
                
                # Extract the View/Edit link for this order to get details
                # Pattern: <a href="/sales-order-view?Key=...">...SO-90210...</a>
                # We need the key specific to this sales order
                # Find the row containing SO-90210, then find the href
                # Simple regex approach: look for the href preceding the reference text
                # HTML structure varies, but usually: <td ...><a href="...">reference</a></td>
                
                # We will try to find the unique key for the order
                # It usually looks like /sales-order-view?Key=...
                # We simply grab the page content of the list and verify the reference and amount are present in the row
                # A more robust check is parsing the row text
                
                # Check for Amount "2,400.00" or "2400.00"
                if "2,400.00" in so_list_page or "2400.00" in so_list_page:
                    RESULT["order_details"]["amount_match_list"] = True
                
                # Check for Customer "Alfreds Futterkiste"
                if "Alfreds Futterkiste" in so_list_page:
                     RESULT["order_details"]["customer_match_list"] = True
                     
                # Try to get details from view page if possible. 
                # Find link: href="/sales-order-view?Key=88fa..."
                # This is tricky with regex on raw HTML.
                # Let s assume list page verification is decent, but lets try to get the detail page.
                
                # Find all view links
                view_links = re.findall(r"/sales-order-view\?[^\"]+", so_list_page)
                
                # Iterate through top 3 recent orders to find the one matching our ref
                for link in view_links[:5]:
                    detail_resp = s.get(f"{MANAGER_URL}{link}")
                    detail_text = detail_resp.text
                    if "SO-90210" in detail_text:
                        # Found specific order
                        RESULT["order_details"]["found_detail"] = True
                        RESULT["order_details"]["reference"] = "SO-90210"
                        
                        # Check customer in detail
                        if "Alfreds Futterkiste" in detail_text:
                            RESULT["order_details"]["customer"] = "Alfreds Futterkiste"
                            
                        # Check Line Item
                        if "Annual Priority Support Plan 2026" in detail_text:
                             RESULT["order_details"]["description"] = "Annual Priority Support Plan 2026"
                        
                        # Check Amount
                        # Manager formats numbers nicely, look for "2,400.00"
                        if "2,400.00" in detail_text:
                            RESULT["order_details"]["total"] = 2400.00
                        break
        else:
             RESULT["module_enabled"] = False

except Exception as e:
    RESULT["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(RESULT, f)
'

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="