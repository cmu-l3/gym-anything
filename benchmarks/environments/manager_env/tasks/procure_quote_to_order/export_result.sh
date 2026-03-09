#!/bin/bash
# Export script for procure_quote_to_order
# Verifies module status and existence of Quote/Order via API

echo "=== Exporting results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# Python script to scrape state
# ------------------------------------------------------------------
python3 - << 'EOF' > /tmp/task_result.json
import requests
import re
import json
import time

URL = "http://localhost:8080"
S = requests.Session()
RESULT = {
    "purchase_quotes_enabled": False,
    "quote_found": False,
    "order_found": False,
    "quote_details": {},
    "order_details": {},
    "timestamp": time.time()
}

def get_biz_key(html):
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", html)
    if not m: m = re.search(r"start\?([^\"&\s]+)", html)
    return m.group(1) if m else None

def clean_money(text):
    if not text: return 0.0
    return float(re.sub(r"[^0-9.]", "", text))

try:
    # Login
    S.post(f"{URL}/login", data={"Username": "administrator"}, timeout=10)
    
    # Get Business Key
    resp = S.get(f"{URL}/businesses", timeout=10)
    key = get_biz_key(resp.text)
    if not key:
        raise Exception("No business key")

    # 1. Check if Purchase Quotes module is enabled
    # We check if the link exists in the sidebar on the summary page
    summary_resp = S.get(f"{URL}/summary?{key}", timeout=10)
    if "Purchase Quotes" in summary_resp.text:
        RESULT["purchase_quotes_enabled"] = True

    # 2. Find the Purchase Quote
    # Navigate to Purchase Quotes list
    quotes_resp = S.get(f"{URL}/purchase-quotes?{key}", timeout=10)
    
    # Look for Exotic Liquids in the list
    # The list contains links to edit/view. We look for a row with the supplier name.
    # Manager.io HTML structure varies, but rows typically contain cell data.
    if "Exotic Liquids" in quotes_resp.text:
        # Extract the View/Edit link for the last quote
        # Regex to find href for a quote line containing Exotic Liquids
        # <td class="...">Exotic Liquids</td>...<a href="purchase-quote-view?Key=...">
        # We'll just grab the first link that looks like a purchase quote view
        m_quote = re.search(r"purchase-quote-view\?Key=([a-zA-Z0-9-]+)", quotes_resp.text)
        if m_quote:
            q_key = m_quote.group(1)
            # Fetch details
            q_det = S.get(f"{URL}/purchase-quote-view?Key={q_key}", timeout=10).text
            
            RESULT["quote_found"] = True
            RESULT["quote_details"]["supplier"] = "Exotic Liquids" if "Exotic Liquids" in q_det else "Unknown"
            # Check for line items
            if "Chai" in q_det:
                RESULT["quote_details"]["item"] = "Chai"
            
            # Simple text search for quantities/prices in the view
            # This is heuristic but usually sufficient for "100" and "15.00" appearing in the table
            RESULT["quote_details"]["has_100"] = "100" in q_det
            RESULT["quote_details"]["has_15"] = "15.00" in q_det or "15" in q_det

    # 3. Find the Purchase Order
    orders_resp = S.get(f"{URL}/purchase-orders?{key}", timeout=10)
    if "Exotic Liquids" in orders_resp.text:
        m_order = re.search(r"purchase-order-view\?Key=([a-zA-Z0-9-]+)", orders_resp.text)
        if m_order:
            o_key = m_order.group(1)
            o_det = S.get(f"{URL}/purchase-order-view?Key={o_key}", timeout=10).text
            
            RESULT["order_found"] = True
            RESULT["order_details"]["supplier"] = "Exotic Liquids" if "Exotic Liquids" in o_det else "Unknown"
            if "Chai" in o_det:
                RESULT["order_details"]["item"] = "Chai"
            RESULT["order_details"]["has_100"] = "100" in o_det
            RESULT["order_details"]["has_15"] = "15.00" in o_det or "15" in o_det

except Exception as e:
    RESULT["error"] = str(e)

print(json.dumps(RESULT, indent=2))
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="