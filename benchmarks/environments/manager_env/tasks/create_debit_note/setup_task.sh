#!/bin/bash
set -e
echo "=== Setting up Create Debit Note task ==="

source /workspace/scripts/task_utils.sh

# 1. timestamp
date +%s > /tmp/task_start_time.txt

# 2. Ensure Manager is running
wait_for_manager 60

# 3. Record initial debit note count for anti-gaming
# We use a python script to scrape the local endpoint since we are inside the container
cat > /tmp/count_debit_notes.py << 'EOF'
import requests
import re
import sys

try:
    url = "http://localhost:8080"
    s = requests.Session()
    # Login
    s.post(f"{url}/login", data={"Username": "administrator"}, timeout=5)
    
    # Get Business Key
    resp = s.get(f"{url}/businesses", timeout=5)
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', resp.text)
    
    if not m:
        print("0")
        sys.exit(0)
        
    biz_key = m.group(1)
    
    # Get Debit Notes
    resp = s.get(f"{url}/debit-notes?{biz_key}", timeout=5)
    # Count occurrences of specific view link or rows
    # Each row usually has a view link like <a href="/debit-note-view?...">
    count = len(re.findall(r'href="[^"]*debit-note-view', resp.text))
    print(count)
    
    # Save biz key for export script
    with open("/tmp/biz_key.txt", "w") as f:
        f.write(biz_key)
        
except Exception as e:
    print("0")
EOF

INITIAL_COUNT=$(python3 /tmp/count_debit_notes.py)
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial debit note count: $INITIAL_COUNT"

# 4. Open Manager at Debit Notes
# We use the 'new' action to prompt the agent, or just the list. 
# Task description says "Navigate to... and Create...", but opening at list is helpful.
open_manager_at "debit_notes"

# 5. Capture initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="