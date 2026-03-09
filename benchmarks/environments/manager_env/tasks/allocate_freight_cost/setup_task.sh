#!/bin/bash
echo "=== Setting up allocate_freight_cost task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is running and accessible
wait_for_manager 60

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Capture initial invoice count (to verify a new one is created)
# We use a python script to robustly fetch this from the web interface
cat > /tmp/get_initial_state.py << 'EOF'
import requests
import re
import sys

BASE_URL = "http://localhost:8080"
TIMEOUT = 5

def get_business_key():
    try:
        r = requests.get(f"{BASE_URL}/businesses", timeout=TIMEOUT)
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
        if not m:
            m = re.search(r'start\?([^"&\s]+)', r.text)
        return m.group(1) if m else None
    except:
        return None

def get_invoice_count(key):
    if not key: return 0
    try:
        r = requests.get(f"{BASE_URL}/purchase-invoices?{key}", timeout=TIMEOUT)
        # Count rows in the table roughly
        return r.text.count('<td') // 4  # Approximation or just raw text search count
    except:
        return 0

key = get_business_key()
count = get_invoice_count(key)
with open('/tmp/initial_invoice_count.txt', 'w') as f:
    f.write(str(count))
EOF

python3 /tmp/get_initial_state.py 2>/dev/null || echo "0" > /tmp/initial_invoice_count.txt

# Open Manager directly to the Purchase Invoices screen to save agent time
echo "Opening Manager.io at Purchase Invoices..."
open_manager_at "purchase_invoices" "new"

# Take initial screenshot for evidence
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="