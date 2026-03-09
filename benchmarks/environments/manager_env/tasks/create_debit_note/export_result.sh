#!/bin/bash
echo "=== Exporting Create Debit Note results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data from Manager.io via local API/Scraping
# We need to find the newly created debit note details
cat > /tmp/extract_debit_note_data.py << 'EOF'
import requests
import re
import json
import os
import time

result = {
    "initial_count": 0,
    "current_count": 0,
    "debit_notes": [],
    "found_target": False,
    "target_details": {}
}

try:
    # Load initial count
    if os.path.exists("/tmp/initial_count.txt"):
        with open("/tmp/initial_count.txt", "r") as f:
            result["initial_count"] = int(f.read().strip())

    # Setup session
    url = "http://localhost:8080"
    s = requests.Session()
    s.post(f"{url}/login", data={"Username": "administrator"}, timeout=5)

    # Get Biz Key
    biz_key = ""
    if os.path.exists("/tmp/biz_key.txt"):
        with open("/tmp/biz_key.txt", "r") as f:
            biz_key = f.read().strip()
    
    if not biz_key:
        # Fallback fetch
        resp = s.get(f"{url}/businesses")
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
        if m:
            biz_key = m.group(1)

    if biz_key:
        # Get Debit Notes List
        list_url = f"{url}/debit-notes?{biz_key}"
        resp = s.get(list_url)
        
        # Parse links to individual debit notes
        # Regex to find view links: href="/debit-note-view?Key=..."
        links = re.findall(r'href="(/debit-note-view\?[^"]+)"', resp.text)
        # Deduplicate
        links = list(set(links))
        
        result["current_count"] = len(links)
        
        # Iterate through notes to find the one matching our criteria
        # We look for "Exotic Liquids" and "350.00" and "DN-001"
        for link in links:
            try:
                note_resp = s.get(f"{url}{link}")
                text = note_resp.text
                
                note_data = {
                    "url": link,
                    "content_snippet": text[:5000] # limiting size
                }
                
                # Simple extraction
                is_target = False
                
                # Check fields in HTML
                if "Exotic Liquids" in text:
                    note_data["supplier"] = "Exotic Liquids"
                
                if "DN-001" in text:
                    note_data["reference"] = "DN-001"
                
                # Check for amount (flexible formatting)
                if re.search(r'350[\.,]00', text) or "350.00" in text:
                    note_data["amount_found"] = True
                    
                # Check description keywords
                if "damaged" in text.lower() and "beverages" in text.lower():
                    note_data["description_found"] = True

                result["debit_notes"].append(note_data)
                
                # Logic to flag the specific target note
                if (note_data.get("supplier") == "Exotic Liquids" and 
                    note_data.get("reference") == "DN-001" and 
                    note_data.get("amount_found")):
                    result["found_target"] = True
                    result["target_details"] = note_data
                    
            except Exception as e:
                print(f"Error parsing note {link}: {e}")

except Exception as e:
    result["error"] = str(e)

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

python3 /tmp/extract_debit_note_data.py

echo "Export complete. Result saved to /tmp/task_result.json"