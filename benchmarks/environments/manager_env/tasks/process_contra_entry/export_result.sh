#!/bin/bash
echo "=== Exporting process_contra_entry results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------------------
# EXTRACT DATA FROM MANAGER.IO
# ---------------------------------------------------------------------------
# We use Python to crawl the local Manager instance and extract the state
# This ensures we get the exact data regardless of UI changes

cat > /tmp/extract_data.py << 'PYEOF'
import requests
import re
import json
import sys

URL = "http://localhost:8080"
S = requests.Session()

result = {
    "customer_exists": False,
    "je_added": False,
    "je_details": {},
    "error": None
}

try:
    # Login
    S.post(f"{URL}/login", data={"Username": "administrator"}, allow_redirects=True)

    # Get Business Key
    biz_page = S.get(f"{URL}/businesses").text
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
    if not m:
        m = re.search(r"start\?([^\"&\s]+)", biz_page)
    
    if not m:
        raise Exception("Could not find Northwind Traders business")
    
    biz_key = m.group(1)

    # 1. Check if Customer "Exotic Liquids" exists
    cust_response = S.get(f"{URL}/customers?{biz_key}")
    if "Exotic Liquids" in cust_response.text:
        result["customer_exists"] = True
    
    # 2. Check Journal Entries
    # We look for the most recent entry
    je_list_response = S.get(f"{URL}/journal-entries?{biz_key}")
    
    # Get initial count
    try:
        with open("/tmp/initial_je_count.txt", "r") as f:
            initial_count = int(f.read().strip())
    except:
        initial_count = 0
        
    current_count = je_list_response.text.count("Edit")
    
    if current_count > initial_count:
        result["je_added"] = True
    
    # Attempt to extract the last Journal Entry details
    # Look for the link to the view/edit page of the top entry
    # Regex to find something like: <td class="..."><a href="journal-entry-view?Key=...">...</a></td>
    # This is brittle to HTML changes, but standard for Manager scraping
    # We look for the "View" link or "Edit" link of the first row (usually most recent if sorted by date)
    
    # Find all View links
    view_links = re.findall(r'href="(journal-entry-view\?Key=[^"]+)"', je_list_response.text)
    
    if view_links:
        # Assuming the first one is the newest (Manager usually lists newest top or bottom? Default is Date desc usually)
        # We will check the first few to find one matching our criteria if possible
        target_link = view_links[0] 
        
        # Get the details of this JE
        je_detail_url = f"{URL}/{target_link}"
        je_text = S.get(je_detail_url).text
        
        # Simple string parsing to avoid complex HTML parser dependency if lxml not present
        # We look for amounts and account names
        
        # Clean up HTML tags for easier searching
        clean_text = re.sub(r'<[^>]+>', ' ', je_text)
        
        result["je_details"]["raw_text"] = clean_text[:2000] # Cap size
        
        # check for specific values in the view
        result["je_details"]["has_exotic"] = "Exotic Liquids" in clean_text
        result["je_details"]["has_payable"] = "Accounts payable" in clean_text or "Accounts Payable" in clean_text
        result["je_details"]["has_receivable"] = "Accounts receivable" in clean_text or "Accounts Receivable" in clean_text
        result["je_details"]["has_200"] = "200.00" in clean_text or "200,00" in clean_text
        
        # Check if 200 appears at least twice (once for debit, once for credit)
        count_200 = clean_text.count("200.00") + clean_text.count("200,00")
        result["je_details"]["amount_count"] = count_200

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run extraction
python3 /tmp/extract_data.py > /tmp/task_result.json

echo "Export completed. Result:"
cat /tmp/task_result.json