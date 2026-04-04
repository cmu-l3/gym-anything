#!/bin/bash
echo "=== Setting up process_expense_claim task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager.io is accessible
wait_for_manager 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial state: Count of Expense Claims (should be 0 or module disabled)
# We use a python script to query the API/Page state safely
python3 -c "
import requests, re, sys
try:
    base_url = 'http://localhost:8080'
    # Login
    s = requests.Session()
    s.post(base_url + '/login', data={'Username': 'administrator'})
    
    # Get Business Key
    r = s.get(base_url + '/businesses')
    m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m:
        m = re.search(r'start\?([^\"&\s]+)', r.text)
    
    if m:
        key = m.group(1)
        # Check initial claims count (if module enabled)
        r_claims = s.get(f'{base_url}/expense-claims?{key}')
        # Simple count of table rows or similar markers
        count = r_claims.text.count('view-item') 
        with open('/tmp/initial_claim_count.txt', 'w') as f:
            f.write(str(count))
    else:
        print('Business not found')
except Exception as e:
    print(e)
"

# Open Firefox at the Summary page of Northwind Traders
# We use the 'summary' module navigation from task_utils
open_manager_at "summary"

# Ensure window is maximized for the agent
sleep 5
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="