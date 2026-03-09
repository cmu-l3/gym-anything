#!/bin/bash
# Export script for acquire_fixed_asset_via_invoice
# Scrapes Manager.io state to verify:
# 1. Fixed Assets module is enabled
# 2. Asset 'MacBook Pro' exists
# 3. Supplier 'TechWorld' exists
# 4. Invoice exists with correct linkage

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We use a Python script to interact with Manager's internal HTTP endpoints
# to robustly extract data without relying on fragile bash regex for HTML.
cat > /tmp/inspect_manager_state.py << 'PYEOF'
import requests
import re
import json
import sys
import time

MANAGER_URL = "http://localhost:8080"
COOKIE_FILE = "/tmp/mgr_cookies.txt"
HEADERS = {"User-Agent": "Mozilla/5.0"}

def get_business_key(session):
    # Get the business key (UUID) for Northwind Traders
    try:
        r = session.get(f"{MANAGER_URL}/businesses", timeout=10)
        # Regex to find the key for Northwind
        # Link looks like: <a href="/summary?FileID=...">Northwind Traders</a>
        # Or newer versions: <a href="/summary?Key=...">Northwind Traders</a>
        m = re.search(r'href="[^"]*\?([^"]+)"[^>]*>Northwind Traders', r.text)
        if m:
            return m.group(1)
        # Fallback: take the first business key found
        m = re.search(r'href="[^"]*\?([^"]+)"', r.text)
        return m.group(1) if m else None
    except Exception as e:
        print(f"Error getting business key: {e}", file=sys.stderr)
        return None

def main():
    s = requests.Session()
    
    # 1. Login (Administrator/Empty)
    try:
        s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, timeout=5)
    except:
        pass # Might already be logged in or no auth

    key = get_business_key(s)
    if not key:
        print(json.dumps({"error": "Could not find business key"}))
        return

    result = {
        "business_key": key,
        "fixed_assets_enabled": False,
        "asset_found": False,
        "asset_id": None,
        "supplier_found": False,
        "supplier_id": None,
        "invoice_found": False,
        "invoice_correct": False,
        "invoice_linkage": False,
        "invoice_amount": 0.0
    }

    # 2. Check if Fixed Assets module is enabled
    # We check the sidebar links on the Summary page
    r = s.get(f"{MANAGER_URL}/summary?{key}")
    if "/fixed-assets?" in r.text:
        result["fixed_assets_enabled"] = True

    # 3. Check for Asset 'MacBook Pro'
    # We look at the Fixed Assets list
    r = s.get(f"{MANAGER_URL}/fixed-assets?{key}")
    if "MacBook Pro" in r.text:
        result["asset_found"] = True
        # Try to extract ID (UUID) from the edit link
        # <td ...><a href="/fixed-asset-form?Key=...&FileID=...">MacBook Pro</a></td>
        # The ID is usually the 'FileID' or part of the query string specific to the item
        # Manager URLs are tricky. Usually /fixed-asset-form?Key=BUSINESS_KEY&Key=ITEM_KEY
        # Let's try to extract the second Key or FileID.
        # Pattern: href="/fixed-asset-form?Key=...&amp;Key=([a-f0-9-]+)"
        m = re.search(r'fixed-asset-form\?[^"]*Key=([a-f0-9-]{36})', r.text)
        if m:
            result["asset_id"] = m.group(1)
            # Ensure this ID is NOT the business key
            if result["asset_id"] == key:
                # Try finding another UUID in the string
                parts = re.findall(r'([a-f0-9-]{36})', m.group(0))
                for p in parts:
                    if p != key:
                        result["asset_id"] = p
                        break

    # 4. Check for Supplier 'TechWorld'
    r = s.get(f"{MANAGER_URL}/suppliers?{key}")
    if "TechWorld" in r.text:
        result["supplier_found"] = True
        m = re.search(r'supplier-form\?[^"]*Key=([a-f0-9-]{36})', r.text)
        if m:
            # Logic to extract exact UUID similar to above might be needed, 
            # but simple string check is often enough for existence.
            pass

    # 5. Check Purchase Invoices
    # We need to find the invoice for TechWorld and inspect it.
    r = s.get(f"{MANAGER_URL}/purchase-invoices?{key}")
    
    # We iterate through rows to find one with "TechWorld" and "2,500.00"
    # This is a bit rough with regex on HTML, but sufficient for verification.
    if "TechWorld" in r.text:
        # Find the View/Edit link for the invoice
        # Look for a row containing TechWorld
        rows = r.text.split('</tr>')
        for row in rows:
            if "TechWorld" in row and ("2,500.00" in row or "2500.00" in row):
                result["invoice_found"] = True
                
                # Extract the link to the invoice view/edit
                # <a href="/purchase-invoice-view?Key=...&Key=INVOICE_ID">
                m_link = re.search(r'href="(/purchase-invoice-view\?[^"]+)"', row)
                if m_link:
                    view_url = m_link.group(1)
                    # Fetch invoice details
                    r_inv = s.get(f"{MANAGER_URL}{view_url}")
                    
                    # Check for Amount
                    if "2,500.00" in r_inv.text or "2500.00" in r_inv.text:
                        result["invoice_correct"] = True
                        result["invoice_amount"] = 2500.00
                    
                    # Check for Linkage to Fixed Asset
                    # In the view mode, it should list "Fixed assets" and "MacBook Pro"
                    # Or "Fixed assets - at cost"
                    if ("Fixed assets" in r_inv.text) and ("MacBook Pro" in r_inv.text):
                        result["invoice_linkage"] = True
                break

    print(json.dumps(result))

if __name__ == "__main__":
    main()
PYEOF

# Run the python script
echo "Running inspection script..."
python3 /tmp/inspect_manager_state.py > /tmp/manager_state.json 2>/dev/null

# Add timestamps and metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APP_RUNNING="false"
if pgrep -f "java" > /dev/null || docker ps | grep -q manager; then
    APP_RUNNING="true"
fi

# Merge into final result
jq -n \
    --argjson state "$(cat /tmp/manager_state.json 2>/dev/null || echo '{}')" \
    --arg start "$TASK_START" \
    --arg end "$TASK_END" \
    --arg app "$APP_RUNNING" \
    '{
        manager_state: $state,
        task_start: $start,
        task_end: $end,
        app_running: $app,
        screenshot_path: "/tmp/task_final.png"
    }' > /tmp/task_result.json

echo "Result JSON:"
cat /tmp/task_result.json

echo "=== Export Complete ==="