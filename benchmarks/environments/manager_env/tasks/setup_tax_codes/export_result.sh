#!/bin/bash
# Export script for setup_tax_codes task
# Scrapes the Tax Codes page to verify the created items

set -e
echo "=== Exporting setup_tax_codes result ==="

# 1. Take final screenshot (Secondary verification)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
echo "Final screenshot saved."

# 2. Extract Data via Python
# We authenticate, find the Tax Codes page, and parse the table rows.
echo "Extracting tax code data..."
python3 - << 'EOF' > /tmp/task_result.json
import requests
import re
import json
import time
import os

MANAGER_URL = "http://localhost:8080"
OUTPUT = {
    "tax_codes_found": [],
    "total_count": 0,
    "page_accessible": False,
    "timestamp": time.time()
}

try:
    s = requests.Session()
    # Login
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, timeout=10)
    
    # Get Business Key
    resp = s.get(f"{MANAGER_URL}/businesses", timeout=10)
    # Regex to find the key for "Northwind Traders"
    # This matches the pattern start?Key=... or similar
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if not m:
         # Fallback to first business
         m = re.search(r'start\?([^"&\s]+)', resp.text)
    
    if m:
        biz_key = m.group(1)
        
        # Navigate to Settings to find Tax Codes link
        resp = s.get(f"{MANAGER_URL}/settings?{biz_key}", timeout=10)
        
        # Find "Tax Codes" href
        # Manager URLs change, but usually contain 'tax-codes'
        link_match = re.search(r'href="([^"]*tax-codes\?[^"]*)"', resp.text)
        
        if link_match:
            tax_codes_url = f"{MANAGER_URL}/{link_match.group(1)}"
            resp = s.get(tax_codes_url, timeout=10)
            OUTPUT["page_accessible"] = True
            
            # Parse the HTML table roughly
            # Look for table rows containing the tax code names
            # Manager tables usually put the Name in one column and Rate in another
            
            # Simple regex to find rows with our expected names and extract nearby numbers
            # This is a heuristic scraper
            
            # Standard Rate
            if "UK Standard Rate" in resp.text:
                # Try to find the rate in the same row or nearby text
                # Looking for "20%" or "20.00%"
                # We split by "UK Standard Rate" and look at the immediate following text
                parts = resp.text.split("UK Standard Rate")[1][:500]
                rate_match = re.search(r'>\s*([0-9]+(?:\.[0-9]+)?)\s*%', parts)
                rate = float(rate_match.group(1)) if rate_match else 0
                OUTPUT["tax_codes_found"].append({"name": "UK Standard Rate", "rate": rate})
                
            # Reduced Rate
            if "UK Reduced Rate" in resp.text:
                parts = resp.text.split("UK Reduced Rate")[1][:500]
                rate_match = re.search(r'>\s*([0-9]+(?:\.[0-9]+)?)\s*%', parts)
                rate = float(rate_match.group(1)) if rate_match else 0
                OUTPUT["tax_codes_found"].append({"name": "UK Reduced Rate", "rate": rate})
            
            OUTPUT["total_count"] = len(OUTPUT["tax_codes_found"])
            
            # Also count total rows in the table to detect extras
            # Manager lists usually have <td ...>
            OUTPUT["raw_row_count"] = resp.text.count("UK Standard Rate") + resp.text.count("UK Reduced Rate") # Approximated
            
        else:
            OUTPUT["error"] = "Could not find Tax Codes link in Settings"
    else:
        OUTPUT["error"] = "Could not find Northwind Traders business"

except Exception as e:
    OUTPUT["error"] = str(e)

print(json.dumps(OUTPUT, indent=2))
EOF

# 3. Add file timestamps/metadata
if [ -f /tmp/task_result.json ]; then
    # Merge with shell-level info
    START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    # Use jq to add fields
    tmp=$(mktemp)
    jq --arg start "$START_TIME" \
       --arg final_ss "/tmp/task_final.png" \
       '. + {task_start_time: $start, screenshot_path: $final_ss}' \
       /tmp/task_result.json > "$tmp" && mv "$tmp" /tmp/task_result.json
fi

echo "Export complete."
cat /tmp/task_result.json