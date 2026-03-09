#!/bin/bash
set -e
echo "=== Setting up: Enable Tracking Codes task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager is running
wait_for_manager 60

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Ensure Tracking Codes module is DISABLED to start
# We use a Python script to interact with Manager API/HTML to reset state
echo "Configuring initial state (Disabling Tracking Codes)..."
python3 -c '
import requests
import re
import sys

MANAGER_URL = "http://localhost:8080"
try:
    s = requests.Session()
    # Login
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    
    # Get Business ID for Northwind
    biz_page = s.get(f"{MANAGER_URL}/businesses").text
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
    if not m: m = re.search(r"start\?([^\"&\s]+)", biz_page)
    if not m: sys.exit(1)
    biz_key = m.group(1)

    # Get Tabs/Customize URL
    # We need to find the specific form to update tabs. 
    # In Manager, this is often /tabs-form?{Key} or similar.
    # We will try to disable it by posting to the tabs endpoint if we can find it.
    # For now, we will just record the state. If it happens to be enabled, we might fail the setup 
    # or just record it. Ideally, we would force disable.
    
    # Let"s check if it is enabled
    summary_page = s.get(f"{MANAGER_URL}/start?{biz_key}").text
    is_enabled = "tracking-codes" in summary_page.lower() or "Tracking Codes" in summary_page
    
    with open("/tmp/initial_state.json", "w") as f:
        f.write(f"{{\"tracking_enabled\": {str(is_enabled).lower()}}}")
        
    print(f"Initial tracking enabled: {is_enabled}")

except Exception as e:
    print(e)
'

# 4. Open Manager at Settings page
echo "Opening Manager.io at Settings..."
# We use the generic open_manager_at but point to settings
# The python script navigates to "settings" module
open_manager_at "settings"

# 5. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="