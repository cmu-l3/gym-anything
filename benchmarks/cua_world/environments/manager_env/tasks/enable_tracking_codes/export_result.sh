#!/bin/bash
set -e
echo "=== Exporting results: Enable Tracking Codes ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Inspect Manager.io state via Python
# We query the application to see if the module is enabled and codes exist
python3 -c '
import requests
import re
import json
import os
import time

MANAGER_URL = "http://localhost:8080"
result = {
    "module_enabled": False,
    "codes_found": [],
    "timestamp": time.time()
}

try:
    s = requests.Session()
    # Login
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

    # Find Business Key
    biz_page = s.get(f"{MANAGER_URL}/businesses").text
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
    if not m: m = re.search(r"start\?([^\"&\s]+)", biz_page)
    
    if m:
        biz_key = m.group(1)
        
        # Check if module is enabled (appears in sidebar/summary)
        summary_resp = s.get(f"{MANAGER_URL}/start?{biz_key}")
        summary_text = summary_resp.text
        if "tracking-codes" in summary_text.lower() or "Tracking Codes" in summary_text:
            result["module_enabled"] = True
            
            # Fetch Tracking Codes list
            # Usually at /tracking-codes?{Key}
            tc_resp = s.get(f"{MANAGER_URL}/tracking-codes?{biz_key}")
            tc_text = tc_resp.text
            
            # Check for specific codes
            targets = ["Sales", "Warehouse", "Administration"]
            for target in targets:
                # Simple string check in the HTML table
                if target in tc_text:
                    result["codes_found"].append(target)
                    
except Exception as e:
    result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
'

# 3. Add file metadata
# Check if initial state file exists to verify we started clean
if [ -f "/tmp/initial_state.json" ]; then
    # Merge initial state into result if possible, or just rely on verifier reading both
    # For simplicity, we just leave them separate, verifier handles logic
    true
fi

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="