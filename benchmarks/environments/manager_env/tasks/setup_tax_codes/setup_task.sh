#!/bin/bash
# Setup script for setup_tax_codes task
# Ensures Manager.io is running, Northwind is loaded, and starts at the Summary page.
# also attempts to clear any existing tax codes with these names to ensure a clean start.

set -e
echo "=== Setting up setup_tax_codes task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager is running
wait_for_manager 60

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Clean up existing tax codes (Anti-gaming / Idempotency)
# We use a python script to log in and check/delete if they exist
echo "Checking for existing tax codes..."
python3 - << 'EOF'
import requests
import re
import sys

MANAGER_URL = "http://localhost:8080"
TAX_NAMES = ["UK Standard Rate", "UK Reduced Rate"]

s = requests.Session()

# Login
try:
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, timeout=10)
    
    # Get Business Key
    resp = s.get(f"{MANAGER_URL}/businesses", timeout=10)
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', resp.text)
    
    if m:
        biz_key = m.group(1)
        print(f"Business Key: {biz_key}")
        
        # Go to Tax Codes page
        # Note: In Manager, Tax Codes are usually at /tax-codes?FileID=...
        # We need to find the link in Settings
        resp = s.get(f"{MANAGER_URL}/settings?{biz_key}", timeout=10)
        
        # Look for Tax Codes link
        # It usually looks like <a href="tax-codes?Key=...">Tax Codes</a>
        # Pattern matching generic link structure
        tc_link = re.search(r'href="([^"]*tax-codes\?[^"]*)"', resp.text)
        
        if tc_link:
            tax_codes_url = f"{MANAGER_URL}/{tc_link.group(1)}"
            resp = s.get(tax_codes_url, timeout=10)
            
            # Simple check: if we see the names, we should ideally delete them.
            # Deletion in Manager requires finding the Delete button/form for a specific item.
            # For simplicity in this setup script, we will just count them to log initial state.
            # Real deletion would be complex without an official API.
            
            count = 0
            for name in TAX_NAMES:
                if name in resp.text:
                    print(f"WARNING: Tax code '{name}' already exists.")
                    count += 1
            
            with open("/tmp/initial_tax_code_count.txt", "w") as f:
                f.write(str(count))
        else:
            print("Could not find Tax Codes link in Settings.")
            with open("/tmp/initial_tax_code_count.txt", "w") as f:
                f.write("0")
    else:
        print("Could not find business.")
except Exception as e:
    print(f"Setup warning: {e}")
EOF

# 4. Launch Firefox at the Summary page
# The agent must click Settings -> Tax Codes manually
echo "Opening Manager.io at Summary page..."
open_manager_at "summary"

# 5. Capture initial screenshot
sleep 5
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="