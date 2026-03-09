#!/bin/bash
echo "=== Setting up setup_foreign_currency_invoice task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is ready
wait_for_manager 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Capture initial state metrics (using a small python script to scrape current counts)
python3 -c '
import requests, re, sys

try:
    s = requests.Session()
    # Login
    s.post("http://localhost:8080/login", data={"Username": "administrator"})
    
    # Get Business Key
    r = s.get("http://localhost:8080/businesses")
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", r.text)
    if not m: m = re.search(r"start\?([^\"&\s]+)", r.text)
    key = m.group(1) if m else ""
    
    if key:
        # Count Invoices
        r_inv = s.get(f"http://localhost:8080/sales-invoices?{key}")
        inv_count = r_inv.text.count("view-sales-invoice") # Rough count based on view links
        
        with open("/tmp/initial_invoice_count.txt", "w") as f:
            f.write(str(inv_count))
            
        print(f"Initial invoice count: {inv_count}")
except Exception as e:
    print(f"Error getting initial state: {e}")
'

# Open Manager at Settings
echo "Opening Manager.io at Settings..."
open_manager_at "settings"

# Take initial screenshot
sleep 5
echo "Capturing initial state screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="