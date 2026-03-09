#!/bin/bash
# Setup script for record_supplier_payment task
# Opens Manager.io at the Payments module

echo "=== Setting up record_supplier_payment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is accessible
wait_for_manager 60

# Record initial count of payments (to detect new additions)
# We use a python script to scrape the count from the API/HTML
python3 -c "
import requests, re
try:
    s = requests.Session()
    # Login
    s.post('http://localhost:8080/login', data={'Username': 'administrator'})
    # Find business
    biz_page = s.get('http://localhost:8080/businesses').text
    m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', biz_page)
    if not m: m = re.search(r'start\?([^\"&\s]+)', biz_page)
    
    if m:
        biz_key = m.group(1)
        # Get Payments page
        resp = s.get(f'http://localhost:8080/payments?{biz_key}')
        # Simple count of rows or IDs
        count = resp.text.count('View') # Rough proxy for rows
        print(count)
    else:
        print('0')
except:
    print('0')
" > /tmp/initial_payment_count.txt

echo "Initial payment count proxy: $(cat /tmp/initial_payment_count.txt)"

# Open Firefox and navigate to Payments module
# Using 'new' action to open the form directly helps the agent but description implies navigation.
# To follow description strictly ("Navigate to..."), we open the list view.
# However, to be helpful and consistent with other tasks, we'll open the list view and let agent click New.
echo "Opening Manager.io Payments module..."
open_manager_at "payments"

# Maximize Firefox (handled by open_manager_at, but double check)
sleep 5
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="