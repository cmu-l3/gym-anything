#!/bin/bash
echo "=== Setting up setup_starting_balances task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager is running and accessible
wait_for_manager 60

# We need to ensure the business exists and is in a clean state (no start date)
# The default setup_data.sh creates Northwind, but we'll double check.

# Navigate to Settings to ensure the agent starts from a neutral but relevant place
# We will start them at the "Summary" page (Dashboard) as stated in the description.
echo "Opening Manager.io at Summary page..."
open_manager_at "summary"

# Record initial state (should be empty/default)
# We'll use a python script to grab the current start date/balances to prove they were empty
cat > /tmp/get_initial_state.py << 'EOF'
import requests
import re
import json

MANAGER_URL = "http://localhost:8080"
s = requests.Session()

def get_business_key():
    try:
        s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, timeout=5)
        r = s.get(f"{MANAGER_URL}/businesses", timeout=5)
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
        if not m: m = re.search(r'start\?([^"&\s]+)', r.text)
        return m.group(1) if m else None
    except:
        return None

key = get_business_key()
if key:
    # Try to get start date page content
    try:
        r = s.get(f"{MANAGER_URL}/start-date-form?{key}", timeout=5)
        # Look for value="2024-07-01" or similar
        date_match = re.search(r'value="(\d{4}-\d{2}-\d{2})"', r.text)
        start_date = date_match.group(1) if date_match else "None"
        print(json.dumps({"start_date": start_date}))
    except:
        print(json.dumps({"error": "Failed to fetch"}))
else:
    print(json.dumps({"error": "No business key"}))
EOF

python3 /tmp/get_initial_state.py > /tmp/initial_state.json 2>/dev/null
echo "Initial state recorded:"
cat /tmp/initial_state.json

# Take initial screenshot
echo "Capturing initial screenshot..."
sleep 5 # Wait for Firefox to load
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="