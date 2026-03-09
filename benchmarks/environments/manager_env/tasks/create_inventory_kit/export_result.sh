#!/bin/bash
echo "=== Exporting create_inventory_kit result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ---------------------------------------------------------------------------
# Verify Data via Python
# ---------------------------------------------------------------------------
python3 -c '
import requests
import sys
import json
import re
import html

MANAGER_URL = "http://localhost:8080"
SESSION = requests.Session()
RESULT = {
    "module_enabled": False,
    "kit_found": False,
    "kit_name": None,
    "kit_price": 0.0,
    "components": [],
    "raw_components_text": ""
}

def login():
    SESSION.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

def get_business_key():
    resp = SESSION.get(f"{MANAGER_URL}/businesses")
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", resp.text)
    if not m: m = re.search(r"start\?([^\"&\s]+)", resp.text)
    return m.group(1) if m else None

try:
    login()
    key = get_business_key()
    if key:
        # 1. Check if Inventory Kits module is enabled (visible in sidebar or tabs)
        # We check the main business page (summary) for the link
        summary_resp = SESSION.get(f"{MANAGER_URL}/summary?{key}")
        if "Inventory Kits" in summary_resp.text or "inventory-kits" in summary_resp.text:
            RESULT["module_enabled"] = True
            
        # 2. Search for the kit
        # List page: /inventory-kits?key
        list_resp = SESSION.get(f"{MANAGER_URL}/inventory-kits?{key}")
        
        # Look for "Holiday Gift Basket" link
        # <a href="inventory-kit-view?Key=...&FileID=...">Holiday Gift Basket</a>
        m_kit = re.search(r"href=\"(inventory-kit-view\?[^\"]+)\">Holiday Gift Basket", list_resp.text)
        
        if m_kit:
            RESULT["kit_found"] = True
            RESULT["kit_name"] = "Holiday Gift Basket"
            view_url = f"{MANAGER_URL}/{m_kit.group(1)}"
            
            # 3. Get Kit Details
            view_resp = SESSION.get(view_url)
            page_text = view_resp.text
            
            # Extract Price
            # Usually shown as 79.99 in a cell or div. Manager view pages are simple HTML tables.
            # We assume the user entered 79.99.
            if "79.99" in page_text:
                RESULT["kit_price"] = 79.99
            else:
                # Try to regex extract a price
                m_price = re.search(r"Sales price.*?([\d,\.]+)", page_text, re.DOTALL | re.IGNORECASE)
                if m_price:
                    try:
                        RESULT["kit_price"] = float(m_price.group(1).replace(",", ""))
                    except: pass
            
            # Extract Components
            # The view page lists components. We will look for component names and quantities.
            # We store text fragments for the verifier to fuzzy match if exact parsing fails.
            
            comp_list = []
            if "Chai Tea" in page_text:
                # Try to find quantity associated
                # Matches row with Chai Tea, look for quantity (usually last col)
                # Simple check: just record existence for now, verifier can do stricter if needed
                # But let"s try to be specific.
                # Common pattern: <td>Chai Tea</td>...<td>2</td>
                m_chai = re.search(r"Chai Tea.*?<td[^>]*>([\d\.]+)</td>", page_text, re.DOTALL)
                qty = float(m_chai.group(1)) if m_chai else 0
                comp_list.append({"name": "Chai Tea", "qty": qty})
            
            if "Extra Virgin Olive Oil" in page_text:
                m_oil = re.search(r"Extra Virgin Olive Oil.*?<td[^>]*>([\d\.]+)</td>", page_text, re.DOTALL)
                qty = float(m_oil.group(1)) if m_oil else 0
                comp_list.append({"name": "Extra Virgin Olive Oil", "qty": qty})
                
            if "Dark Chocolate Assortment" in page_text:
                m_choc = re.search(r"Dark Chocolate Assortment.*?<td[^>]*>([\d\.]+)</td>", page_text, re.DOTALL)
                qty = float(m_choc.group(1)) if m_choc else 0
                comp_list.append({"name": "Dark Chocolate Assortment", "qty": qty})
                
            RESULT["components"] = comp_list
            RESULT["raw_page_snippet"] = page_text[:2000] # Debug
            
except Exception as e:
    RESULT["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(RESULT, f)
'

# Check app running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Update JSON with system metadata
jq --arg ar "$APP_RUNNING" --arg sp "/tmp/task_final.png" \
   '. + {app_running: $ar, screenshot_path: $sp}' \
   /tmp/task_result.json > /tmp/task_result.json.tmp && mv /tmp/task_result.json.tmp /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="