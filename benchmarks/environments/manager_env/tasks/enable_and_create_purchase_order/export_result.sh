#!/bin/bash
echo "=== Exporting enable_and_create_purchase_order results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# QUERY MANAGER.IO API FOR STATE
# -----------------------------------------------------------------------
# We use Python to robustly parse the API/HTML and generate the JSON result

python3 -c '
import requests, re, json, sys, os
from datetime import datetime

MANAGER_URL = "http://localhost:8080"
TASK_START = int(os.environ.get("TASK_START", 0))

result = {
    "module_enabled": False,
    "po_exists": False,
    "po_details": {},
    "api_accessible": False
}

try:
    s = requests.Session()
    # Login
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

    # Get Business Key
    biz_page = s.get(f"{MANAGER_URL}/businesses").text
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
    if not m:
        m = re.search(r"start\?([^\"&\s]+)", biz_page)
    
    if m:
        biz_key = m.group(1)
        result["api_accessible"] = True
        
        # -------------------------------------------------------
        # CHECK 1: Is Purchase Orders Module Enabled?
        # -------------------------------------------------------
        # We check the Summary page for the sidebar link "Purchase Orders"
        summary_page = s.get(f"{MANAGER_URL}/summary?{biz_key}").text
        # The sidebar link usually looks like <a href="/purchase-orders?Key=...">Purchase Orders</a>
        if "purchase-orders?" in summary_page and ">Purchase Orders<" in summary_page:
            result["module_enabled"] = True
            
        # -------------------------------------------------------
        # CHECK 2: Get Purchase Orders Data
        # -------------------------------------------------------
        # Access the purchase orders list JSON
        # Manager.io often exposes data via the same URL with Accept: application/json or just parsing the table
        # We will parse the HTML table or JSON endpoint if available.
        # Since Manager.io Server Edition is often server-side rendered, we parse the HTML of the PO list.
        
        po_list_url = f"{MANAGER_URL}/purchase-orders?{biz_key}"
        po_resp = s.get(po_list_url)
        
        if po_resp.status_code == 200:
            html = po_resp.text
            
            # Look for "Exotic Liquids" in the table
            # Simple check first
            if "Exotic Liquids" in html:
                result["po_exists"] = True
                
                # Try to extract date and amount from the row containing Exotic Liquids
                # Regex to find row with Exotic Liquids and grab surrounding data
                # Row format roughly: <td>Date</td>...<td>Reference</td>...<td>Exotic Liquids</td>...<td>Amount</td>
                
                # Extracting specific values via regex on the table row is brittle but effective for verification
                # We look for the date 2025-06-15 and amount 660.00 in the HTML
                
                if "15/06/2025" in html or "2025-06-15" in html or "15 Jun 2025" in html:
                     result["po_details"]["date_match"] = True
                
                # Check for amount (660.00)
                if "660.00" in html:
                    result["po_details"]["amount_match"] = True
                    result["po_details"]["total_amount"] = 660.00

                # If we want deeper verification, we can click into the Edit link of the PO
                # Find edit link for the PO
                # href="/purchase-order-form?Key=...&FileID=..."
                edit_link_m = re.search(r"href=\"/purchase-order-form\?([^\" >]+)\"[^>]*>Edit", html)
                if not edit_link_m:
                    # Try "View" link if Edit not obvious
                    edit_link_m = re.search(r"href=\"/purchase-order-view\?([^\" >]+)\"", html)
                
                if edit_link_m:
                    sub_url = edit_link_m.group(1)
                    # If it was view, swap to form to see raw values clearly
                    form_url = f"{MANAGER_URL}/purchase-order-form?{sub_url}"
                    form_page = s.get(form_url).text
                    
                    # Check for line items in the form value JSON
                    # value="{...}"
                    val_m = re.search(r"value=\"({.*})\"", form_page)
                    if val_m:
                        try:
                            # The value attribute is HTML escaped, need to unescape
                            import html as html_lib
                            json_str = html_lib.unescape(val_m.group(1))
                            data = json.loads(json_str)
                            
                            result["po_details"]["supplier_name"] = "Exotic Liquids" # inferred if we found it earlier, but checking ID is hard without lookup
                            result["po_details"]["issue_date"] = data.get("IssueDate", "")
                            
                            lines = data.get("Lines", [])
                            result["po_details"]["line_count"] = len(lines)
                            result["po_details"]["lines"] = []
                            
                            total = 0.0
                            for line in lines:
                                desc = line.get("ItemDescription", "") or line.get("Description", "")
                                qty = float(line.get("Qty", 0))
                                price = float(line.get("UnitPrice", 0))
                                total += (qty * price)
                                result["po_details"]["lines"].append({
                                    "description": desc,
                                    "qty": qty,
                                    "price": price
                                })
                            
                            result["po_details"]["calculated_total"] = total
                        except Exception as e:
                            print(f"Error parsing form JSON: {e}")

except Exception as e:
    print(f"Script Error: {e}")

# Save Result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
'

# Handle permission for result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="