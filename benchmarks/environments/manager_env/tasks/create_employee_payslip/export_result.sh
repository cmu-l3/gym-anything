#!/bin/bash
set -e
echo "=== Exporting create_employee_payslip results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Output file
RESULT_FILE="/tmp/task_result.json"
COOKIE_FILE="/tmp/mgr_export_cookies.txt"
MANAGER_URL="http://localhost:8080"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# 1. Login and Get Context
# ==============================================================================
echo "Logging into Manager.io API..."
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" \
    -L -o /dev/null 2>/dev/null

# Get business key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/businesses" -L 2>/dev/null)

BIZ_KEY=$(python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html)
if not m:
    m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
" <<< "$BIZ_PAGE")

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Could not find business key. Cannot verify."
    echo '{"error": "business_not_found"}' > "$RESULT_FILE"
    exit 0
fi

echo "Business Key: $BIZ_KEY"

# ==============================================================================
# 2. Scrape Data using Python
# ==============================================================================
# We use a Python script to robustly parse the HTML responses
# Passing variables via environment
export MANAGER_URL
export BIZ_KEY
export COOKIE_FILE

python3 -c '
import os
import requests
import re
import json
import sys

manager_url = os.environ["MANAGER_URL"]
biz_key = os.environ["BIZ_KEY"]
cookie_file = os.environ["COOKIE_FILE"]

# Load cookies from the curl cookie jar
cookies = {}
try:
    with open(cookie_file, "r") as f:
        for line in f:
            if not line.startswith("#") and line.strip():
                parts = line.split()
                if len(parts) >= 7:
                    cookies[parts[5]] = parts[6]
except Exception as e:
    print(f"Error reading cookies: {e}", file=sys.stderr)

session = requests.Session()
session.cookies.update(cookies)

def check_module(name, endpoint):
    """Check if a module is enabled (page loads successfully)."""
    url = f"{manager_url}/{endpoint}?{biz_key}"
    try:
        r = session.get(url, allow_redirects=True)
        # In Manager, disabled modules typically redirect to Summary or 404/403 equivalent
        # However, Manager often just hides the tab but the URL might still work if manually accessed?
        # A better check is if the text "Customize" is present, or if specific module elements exist.
        # If the module is NOT enabled in tabs, the specific list page usually still renders if you know the URL,
        # BUT the task requires enabling them in the GUI. 
        # For verification, we assume if the user created data, they must have accessed it.
        return {
            "enabled": r.status_code == 200, 
            "content": r.text,
            "url": url
        }
    except:
        return {"enabled": False, "content": "", "url": url}

results = {
    "modules_enabled": {},
    "payslip_items": [],
    "employees": [],
    "payslips": []
}

# ------------------------------------------------------------------
# Check Modules & Content
# ------------------------------------------------------------------

# 1. Employees
print("Checking Employees...", file=sys.stderr)
emp_res = check_module("employees", "employees")
results["modules_enabled"]["employees"] = emp_res["enabled"]
if "Maria Anders" in emp_res["content"]:
    results["employees"].append("Maria Anders")

# 2. Payslip Items
print("Checking Payslip Items...", file=sys.stderr)
psi_res = check_module("payslip-items", "payslip-items")
results["modules_enabled"]["payslip_items"] = psi_res["enabled"]
if "Gross Salary" in psi_res["content"]:
    results["payslip_items"].append("Gross Salary")
if "Income Tax" in psi_res["content"]:
    results["payslip_items"].append("Income Tax Withholding")

# 3. Payslips
print("Checking Payslips...", file=sys.stderr)
ps_res = check_module("payslips", "payslips")
results["modules_enabled"]["payslips"] = ps_res["enabled"]

# Find payslip for Maria Anders
# Look for a link like <a href="/payslip-view?Key=...">Maria Anders</a>
# Or simply check content first
if "Maria Anders" in ps_res["content"]:
    # Extract the view link to check amounts
    # Regex for href="/payslip-view?..." inside a row that likely contains Maria
    # This is a bit heuristic. We look for the view link.
    view_links = re.findall(r"href=\"/payslip-view\?([^\"]+)\"", ps_res["content"])
    
    for link_key in view_links:
        view_url = f"{manager_url}/payslip-view?{link_key}"
        try:
            r_view = session.get(view_url)
            html = r_view.text
            
            # Check if this payslip belongs to Maria
            if "Maria Anders" in html:
                payslip_data = {
                    "id": link_key,
                    "employee": "Maria Anders",
                    "date_found": False,
                    "gross_found": False,
                    "tax_found": False,
                    "net_found": False,
                    "raw_amounts": []
                }
                
                # Check Date (2025-01-31)
                if "31 Jan 2025" in html or "2025-01-31" in html or "31/01/2025" in html:
                    payslip_data["date_found"] = True
                
                # Check Amounts
                # Manager displays amounts like 4,500.00
                # We look for simple string matches first
                if "4,500.00" in html or "4500.00" in html:
                    payslip_data["gross_found"] = True
                if "675.00" in html:
                    payslip_data["tax_found"] = True
                if "3,825.00" in html or "3825.00" in html:
                    payslip_data["net_found"] = True
                    
                results["payslips"].append(payslip_data)
                break # Assuming only one payslip created for this task
        except Exception as e:
            print(f"Failed to fetch payslip detail: {e}", file=sys.stderr)

# ------------------------------------------------------------------
# Output Results
# ------------------------------------------------------------------
print(json.dumps(results, indent=2))
' > "$RESULT_FILE"

# Save permissions
chmod 666 "$RESULT_FILE"

echo "Results exported to $RESULT_FILE"
echo "=== Export complete ==="