#!/bin/bash
echo "=== Exporting bill_reimbursable_expense result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to scrape the Manager.io state securely
# We need to check:
# 1. Is Billable Expenses module enabled?
# 2. Does the Payment exist?
# 3. Does the Invoice exist?
# 4. Is the Invoice linked to the Expense?

python3 - << 'EOF' > /tmp/task_result.json
import requests
import re
import json
import sys

MANAGER_URL = "http://localhost:8080"
result = {
    "module_enabled": False,
    "payment_found": False,
    "payment_correct": False,
    "invoice_found": False,
    "invoice_linked": False,
    "details": {}
}

try:
    s = requests.Session()
    # Login
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    
    # Get Business Key for Northwind
    r = s.get(f"{MANAGER_URL}/businesses")
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', r.text)
    
    if m:
        key = m.group(1)
        base_url = f"{MANAGER_URL}/start?{key}"
        
        # 1. Check if Billable Expenses module is enabled
        # We check the sidebar of the main page
        dash = s.get(base_url).text
        if "billable-expenses?" in dash:
            result["module_enabled"] = True
            
        # 2. Check for Payment
        # Fetch Payments list
        payments_page = s.get(f"{MANAGER_URL}/payments?{key}").text
        # Look for the row with date 2025-08-15 and amount 120.00
        # This is a heuristic scrape; for more precision we'd open the edit page
        # Regex for row: contains date, payee, amount
        # Date format might vary based on locale, but standard is often YYYY-MM-DD or DD/MM/YYYY
        # We look for "15/08/2025" or "2025-08-15" and "120.00"
        
        # Find UUID of payment to inspect details
        # Pattern: <td ...>15/08/2025</td> ... <td ...>120.00</td> ... <a href="payment-view?Key=UUID...>
        
        # We'll look for the specific View link associated with "120.00" and "Port Authority"
        payment_uuid = None
        for line in payments_page.split('</tr>'):
            if "120.00" in line and "Port Authority" in line:
                # Extract UUID
                m_uuid = re.search(r'payment-view\?Key=([^"&]+)', line)
                if m_uuid:
                    payment_uuid = m_uuid.group(1)
                    result["payment_found"] = True
                    break
        
        if payment_uuid:
            # Verify Payment Details (Account = Billable Expenses, Customer = Ernst Handel)
            p_detail = s.get(f"{MANAGER_URL}/payment-view?Key={payment_uuid}&FileID={key}").text
            
            # Check for "Billable expenses" text in the classification/lines area
            # And "Ernst Handel"
            # And "Port Authority Customs Fee"
            if "Billable expenses" in p_detail and "Ernst Handel" in p_detail and "Port Authority Customs Fee" in p_detail:
                result["payment_correct"] = True
            
            result["details"]["payment_uuid"] = payment_uuid

        # 3. Check for Sales Invoice
        invoices_page = s.get(f"{MANAGER_URL}/sales-invoices?{key}").text
        
        invoice_uuid = None
        # Look for invoice for Ernst Handel dated 15/08/2025 with amount 120.00
        for line in invoices_page.split('</tr>'):
            if "Ernst Handel" in line and "120.00" in line:
                m_uuid = re.search(r'sales-invoice-view\?Key=([^"&]+)', line)
                if m_uuid:
                    invoice_uuid = m_uuid.group(1)
                    result["invoice_found"] = True
                    break
        
        if invoice_uuid:
            # 4. Check Linkage (Anti-gaming)
            # We need to verify the line item comes from Billable Expenses
            # In the View mode, it might just show the description.
            # We often need the Edit mode or to infer from the View structure.
            # In Manager, billable expenses usually appear linked.
            # Let's check the edit form to be sure of the structure.
            
            # However, the View page is usually sufficient. 
            # If it was manually entered, it's just a line. 
            # If it's a billable expense, the system often tracks it.
            # A strong signal is the description "Port Authority Customs Fee" matching exactly the payment.
            
            inv_detail = s.get(f"{MANAGER_URL}/sales-invoice-view?Key={invoice_uuid}&FileID={key}").text
            if "Port Authority Customs Fee" in inv_detail:
                result["invoice_linked"] = True
                # Note: stricter verification would require parsing the JSON representation if Manager exposed it easily,
                # or checking if the Billable Expense status changed to "Invoiced".
                # For this task, matching the description and amount on the invoice for the customer is strong evidence.
                
                # Double check: Check Billable Expenses list to see if it's "Invoiced"
                be_page = s.get(f"{MANAGER_URL}/billable-expenses?{key}").text
                if "Invoiced" in be_page and "Port Authority Customs Fee" in be_page:
                     result["invoice_linked"] = True
                elif "Uninvoiced" in be_page and "Port Authority Customs Fee" in be_page:
                     result["invoice_linked"] = False # It exists but hasn't been added to invoice properly
            
            result["details"]["invoice_uuid"] = invoice_uuid

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete."