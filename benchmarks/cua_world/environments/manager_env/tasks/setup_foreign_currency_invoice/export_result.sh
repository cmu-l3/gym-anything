#!/bin/bash
echo "=== Exporting setup_foreign_currency_invoice result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
take_screenshot /tmp/task_final.png

# Run Python script to scrape Manager.io state
python3 - << 'EOF'
import requests
import re
import json
import sys
import os

RESULT_FILE = "/tmp/task_result.json"
MANAGER_URL = "http://localhost:8080"

result = {
    "base_currency_set": False,
    "foreign_currency_exists": False,
    "exchange_rate": 0.0,
    "customer_currency_set": False,
    "invoice_exists": False,
    "invoice_details": {},
    "initial_invoice_count": 0,
    "final_invoice_count": 0,
    "scraped_successfully": False
}

try:
    # Read initial invoice count
    if os.path.exists("/tmp/initial_invoice_count.txt"):
        with open("/tmp/initial_invoice_count.txt", "r") as f:
            result["initial_invoice_count"] = int(f.read().strip() or 0)

    s = requests.Session()
    # Login
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"})
    
    # Get Business Key
    r = s.get(f"{MANAGER_URL}/businesses")
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', r.text)
    
    if m:
        biz_key = m.group(1)
        result["scraped_successfully"] = True
        
        # 1. Check Base Currency
        # Base currency is usually shown on Settings or Summary. 
        # In settings, we check the "Base Currency" page content if accessible, or check Summary.
        # Let's check Summary page text for "Base Currency: USD" or similar, 
        # OR check the Base Currency settings page explicitly.
        r_settings = s.get(f"{MANAGER_URL}/base-currency-form?{biz_key}")
        if "USD" in r_settings.text and "United States Dollar" in r_settings.text:
             # If it's a form value or selected
             if 'value="USD"' in r_settings.text or 'selected' in r_settings.text: # Basic heuristics
                 result["base_currency_set"] = True
        # Stronger check: Look at the page title or summary
        
        # 2. Check Foreign Currencies
        r_currencies = s.get(f"{MANAGER_URL}/currencies?{biz_key}")
        if "EUR" in r_currencies.text and "Euro" in r_currencies.text:
            result["foreign_currency_exists"] = True
            # Try to extract exchange rate
            # Look for table row with EUR, then finding the rate
            # Regex approximation: EUR.*?<td...?>.*?([0-9]+\.[0-9]+).*?</td>
            m_rate = re.search(r'EUR.*?([0-9]+\.[0-9]+)', r_currencies.text, re.DOTALL)
            if m_rate:
                try:
                    result["exchange_rate"] = float(m_rate.group(1))
                except:
                    pass
        
        # 3. Check Customer (Alfreds Futterkiste)
        # First find the customer link
        r_cust_list = s.get(f"{MANAGER_URL}/customers?{biz_key}")
        m_cust = re.search(r'customer-form\?Key=([^"&\s]+)[^>]*>Alfreds Futterkiste', r_cust_list.text)
        if m_cust:
            cust_key = m_cust.group(1)
            # Fetch customer details
            r_cust_detail = s.get(f"{MANAGER_URL}/customer-form?Key={cust_key}&{biz_key}")
            # Check if EUR is selected/present in the form
            if "EUR" in r_cust_detail.text:
                result["customer_currency_set"] = True
        
        # 4. Check Sales Invoice
        r_inv_list = s.get(f"{MANAGER_URL}/sales-invoices?{biz_key}")
        result["final_invoice_count"] = r_inv_list.text.count("view-sales-invoice")
        
        # Search for the specific invoice details in the list
        # Look for row containing "Alfreds Futterkiste" AND "2,500.00" AND "INV-EUR-001"
        # Note: formatting might be 2,500.00 or 2500.00.
        
        text = r_inv_list.text
        if "Alfreds Futterkiste" in text and ("2,500.00" in text or "2500.00" in text) and "INV-EUR-001" in text:
            result["invoice_exists"] = True
            
            # Extract date if possible
            if "2025-01-15" in text or "15/01/2025" in text or "Jan 15, 2025" in text:
                 result["invoice_details"]["date_correct"] = True
            else:
                 result["invoice_details"]["date_correct"] = False
                 
            # Check for currency symbol if visible in list (often € or EUR)
            if "€" in text or "EUR" in text:
                result["invoice_details"]["currency_symbol_found"] = True

except Exception as e:
    result["error"] = str(e)

# Save result
with open(RESULT_FILE, "w") as f:
    json.dump(result, f, indent=2)
    
print(json.dumps(result, indent=2))
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="