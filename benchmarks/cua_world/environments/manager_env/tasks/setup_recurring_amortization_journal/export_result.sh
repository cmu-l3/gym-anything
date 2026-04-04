#!/bin/bash
echo "=== Exporting Recurring Amortization Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Source task utils
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------------------
# Python script to scrape Manager.io state via HTTP
# ---------------------------------------------------------------------------
python3 -c '
import requests
import re
import json
import sys
import os

MANAGER_URL = "http://localhost:8080"
OUTPUT_FILE = "/tmp/task_result.json"

def scrape_manager():
    s = requests.Session()
    
    # 1. Login
    try:
        s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, timeout=10)
    except Exception as e:
        return {"error": f"Login failed: {str(e)}"}

    # 2. Get Business Key for "Northwind Traders"
    try:
        biz_page = s.get(f"{MANAGER_URL}/businesses", timeout=10).text
        # Look for the link associated with Northwind Traders
        # Pattern: <a href="start?FileID=...">Northwind Traders</a>
        # Using a regex that captures the key
        m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
        if not m:
            # Fallback for generic structure
            m = re.search(r"start\?([^\"&\s]+)", biz_page)
        
        if not m:
            return {"error": "Could not find Northwind Traders business key"}
            
        biz_key = m.group(1)
        # "Enter" the business to set session context
        s.get(f"{MANAGER_URL}/start?{biz_key}", timeout=10)
        
    except Exception as e:
        return {"error": f"Business lookup failed: {str(e)}"}

    results = {
        "business_key": biz_key,
        "accounts_found": [],
        "recurring_entries_found": [],
        "chart_of_accounts_html": "",
        "recurring_entries_html": ""
    }

    # 3. Fetch Chart of Accounts
    # Typically at /chart-of-accounts or via Settings
    # We will try the direct URL pattern. Note: Manager URLs often look like /chart-of-accounts?FileID=...
    # Since we are in the session (cookies), we might just need the path if using relative, 
    # but Manager usually appends the FileID/Key to every link.
    
    # Let"s try to find the link to Chart of Accounts from the Settings page
    try:
        settings_page = s.get(f"{MANAGER_URL}/settings?{biz_key}", timeout=10).text
        
        # Find Chart of Accounts link
        # Pattern: <a href="chart-of-accounts?FileID=...">Chart of Accounts</a>
        coa_link_match = re.search(r"href=\"(chart-of-accounts\?[^\"]+)\"", settings_page)
        
        if coa_link_match:
            coa_url = f"{MANAGER_URL}/{coa_link_match.group(1)}"
            coa_page = s.get(coa_url, timeout=10).text
            results["chart_of_accounts_html"] = coa_page
            
            # Simple check for our target accounts in the HTML
            if "Prepaid Insurance" in coa_page:
                results["accounts_found"].append("Prepaid Insurance")
            if "Insurance Expense" in coa_page:
                results["accounts_found"].append("Insurance Expense")
        else:
            # Try guessing the URL
            coa_page = s.get(f"{MANAGER_URL}/chart-of-accounts?{biz_key}", timeout=10).text
            if "Chart of Accounts" in coa_page:
                results["chart_of_accounts_html"] = coa_page
                if "Prepaid Insurance" in coa_page:
                    results["accounts_found"].append("Prepaid Insurance")
                if "Insurance Expense" in coa_page:
                    results["accounts_found"].append("Insurance Expense")

    except Exception as e:
        results["coa_error"] = str(e)

    # 4. Fetch Recurring Journal Entries
    try:
        # Try to find link in Settings page first
        # Pattern: <a href="recurring-journal-entries?FileID=...">Recurring Journal Entries</a>
        rje_link_match = re.search(r"href=\"(recurring-journal-entries\?[^\"]+)\"", settings_page)
        
        rje_page = None
        if rje_link_match:
            rje_url = f"{MANAGER_URL}/{rje_link_match.group(1)}"
            rje_page = s.get(rje_url, timeout=10).text
        else:
            # Try guessing URL
            rje_page = s.get(f"{MANAGER_URL}/recurring-journal-entries?{biz_key}", timeout=10).text

        if rje_page:
            results["recurring_entries_html"] = rje_page
            
            # Basic scraping of the list
            # We look for the description and amount
            if "Monthly Insurance Amortization" in rje_page:
                entry = {"description": "Monthly Insurance Amortization"}
                # Try to extract context (e.g. amount) nearby
                # This is a rough check; real verification might need parsing the HTML table structure
                # We save the HTML to let the verifier do robust soup parsing if needed
                # But for now, simple string checks
                if "1,000.00" in rje_page or "1000.00" in rje_page:
                     entry["amount_match"] = True
                if "Monthly" in rje_page:
                     entry["interval_match"] = True
                results["recurring_entries_found"].append(entry)
                
    except Exception as e:
        results["rje_error"] = str(e)

    return results

data = scrape_manager()
data["task_start"] = int(os.environ.get("TASK_START", 0))
data["task_end"] = int(os.environ.get("TASK_END", 0))

with open(OUTPUT_FILE, "w") as f:
    json.dump(data, f, indent=2)

' 

echo "=== Export Complete ==="