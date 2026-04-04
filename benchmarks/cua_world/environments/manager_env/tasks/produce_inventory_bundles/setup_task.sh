#!/bin/bash
# Setup script for produce_inventory_bundles task
# Ensures Manager.io is running and records initial state.

echo "=== Setting up produce_inventory_bundles task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager.io is ready
wait_for_manager 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create a Python script to check initial state (anti-gaming)
# We want to know if 'Beverage Bundle' already exists (it shouldn't)
cat > /tmp/check_initial.py << 'EOF'
import requests
import re
import sys

BASE_URL = "http://localhost:8080"
S = requests.Session()

def login():
    S.post(f"{BASE_URL}/login", data={"Username": "administrator"}, timeout=10)

def get_business_key():
    resp = S.get(f"{BASE_URL}/businesses", timeout=10)
    # Match Northwind Traders key
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', resp.text)
    return m.group(1) if m else None

def check_item_exists(key, code):
    # Retrieve inventory items list
    resp = S.get(f"{BASE_URL}/inventory-items?{key}", timeout=10)
    if code in resp.text:
        return True
    return False

try:
    login()
    key = get_business_key()
    if key:
        exists = check_item_exists(key, "BUNDLE-2025")
        with open("/tmp/initial_bundle_exists.txt", "w") as f:
            f.write("true" if exists else "false")
except Exception as e:
    print(f"Setup check failed: {e}")
EOF

python3 /tmp/check_initial.py 2>/dev/null || true

# Open Manager.io at the Summary page (Dashboard)
# The agent must navigate to Settings/Customize themselves to enable the module
echo "Opening Manager.io at Summary page..."
open_manager_at "summary"

echo "=== Setup complete ==="