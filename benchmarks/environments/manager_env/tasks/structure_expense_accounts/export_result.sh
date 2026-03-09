#!/bin/bash
echo "=== Exporting structure_expense_accounts results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We need to scrape the Manager.io state to verify the hierarchy.
# We will use a python script to log in and fetch the Chart of Accounts and P&L.

cat > /tmp/scrape_accounts.py << 'PYEOF'
import requests
import re
import json
import sys

MANAGER_URL = "http://localhost:8080"
COOKIE_FILE = "/tmp/mgr_cookies.txt"

def get_business_key(session):
    try:
        resp = session.get(f"{MANAGER_URL}/businesses")
        # Look for Northwind Traders link
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
        if not m:
            m = re.search(r'start\?([^"&\s]+)', resp.text)
        return m.group(1) if m else None
    except Exception as e:
        return None

def main():
    s = requests.Session()
    
    # 1. Login
    try:
        s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, timeout=5)
    except:
        pass # Might already be logged in or no auth

    # 2. Get Business Key
    biz_key = get_business_key(s)
    if not biz_key:
        print(json.dumps({"error": "Could not find business key"}))
        return

    # 3. Fetch Chart of Accounts page (HTML)
    # This page usually lists the structure.
    # We look for the "Chart of Accounts" endpoint.
    coa_url = f"{MANAGER_URL}/chart-of-accounts?{biz_key}"
    try:
        r_coa = s.get(coa_url)
        coa_html = r_coa.text
    except:
        coa_html = ""

    # 4. Fetch Profit and Loss Statement (to verify grouping affects reports)
    # We need to find the Reports link, then P&L link.
    # Simpler: P&L is usually accessible via a specific report view if created.
    # Since P&L is dynamic, we might just rely on COA structure.
    # Let's check the Groups endpoint if possible, or just parse COA HTML.

    result = {
        "business_key": biz_key,
        "coa_html_snippet": coa_html, # We'll parse this in verifier or here
        "facility_costs_group_found": "Facility Costs" in coa_html,
        "warehouse_rent_found": "Warehouse Rent" in coa_html,
        "shop_electricity_found": "Shop Electricity" in coa_html,
        "timestamp": 0 # Placeholder
    }
    
    # Simple hierarchy check via string find in HTML
    # In Manager HTML, nested items usually follow their group or have indentation classes.
    # We will save the raw HTML to analyzing in the verifier.
    
    print(json.dumps(result))

if __name__ == "__main__":
    main()
PYEOF

# Run the scraper
SCRAPE_RESULT=$(python3 /tmp/scrape_accounts.py)

# Check application status
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then APP_RUNNING="true"; fi

# Combine into final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "scrape_result": $SCRAPE_RESULT,
    "app_was_running": $APP_RUNNING,
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"