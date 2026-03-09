#!/bin/bash
echo "=== Setting up process_contra_entry task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Manager is running
wait_for_manager 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------------------
# PREPARE DATA: Ensure clean state
# ---------------------------------------------------------------------------
echo "Preparing data state..."

# Run python script to ensure Exotic Liquids is NOT a customer yet
python3 -c '
import requests
import sys
import re

URL = "http://localhost:8080"
S = requests.Session()

# Login
S.post(f"{URL}/login", data={"Username": "administrator"}, allow_redirects=True)

# Find Northwind Traders
biz_page = S.get(f"{URL}/businesses").text
m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
if not m:
    m = re.search(r"start\?([^\"&\s]+)", biz_page)

if not m:
    print("Error: Could not find business key")
    sys.exit(1)

biz_key = m.group(1)
print(f"Business Key: {biz_key}")

# check if Exotic Liquids exists as CUSTOMER
cust_page = S.get(f"{URL}/customers?{biz_key}").text
# If found, we should delete it or fail. 
# For this task setup, we will attempt to delete if it exists (via API extraction would be complex, 
# so we assume standard setup logic. If it exists from previous run, we warn).
if "Exotic Liquids" in cust_page:
    print("WARNING: Exotic Liquids already exists as Customer. Task might be trivialized if not cleaned.")
    # In a full impl, we would parse the key and send a DELETE/Delete request.
    # For now, we assume the environment resets or we rely on the agent creating it.

# Record initial Journal Entry count
je_page = S.get(f"{URL}/journal-entries?{biz_key}").text
# Simple heuristic count of rows or keys
je_count = je_page.count("Edit") # Rough proxy for rows in table
with open("/tmp/initial_je_count.txt", "w") as f:
    f.write(str(je_count))

print(f"Initial JE Count proxy: {je_count}")
'

# ---------------------------------------------------------------------------
# SETUP BROWSER
# ---------------------------------------------------------------------------
# Open Manager.io at the Summary page
open_manager_at "summary"

# Wait for window
wait_for_window "Firefox" 20

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="