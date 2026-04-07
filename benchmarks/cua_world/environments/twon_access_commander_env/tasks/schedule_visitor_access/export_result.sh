#!/bin/bash
echo "=== Exporting schedule_visitor_access result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Ensure we have fresh API session
ac_login

# Use Python to deeply query the API and build a reliable JSON state export
# Since 2N API structures for visitors/credentials can vary slightly by version,
# we dump the raw matching objects and let the verifier inspect them.
cat > /tmp/export_data.py << 'EOF'
import requests
import json
import urllib3
import os

urllib3.disable_warnings()

# Parse session cookies
cookies = {}
try:
    with open('/tmp/ac_cookies.txt', 'r') as f:
        for line in f:
            if not line.startswith('#') and line.strip():
                parts = line.strip().split('\t')
                if len(parts) >= 7:
                    cookies[parts[5]] = parts[6]
except Exception as e:
    print(f"Warning: Could not read cookies: {e}")

s = requests.Session()
s.cookies.update(cookies)
s.verify = False
base = "https://localhost:9443/api/v3"

result = {
    "task_start_time": 0,
    "sandra_id": None,
    "elias_target": None,
    "api_source": None
}

# Get task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result["task_start_time"] = int(f.read().strip())
except:
    pass

# Get Sandra's ID
try:
    with open('/tmp/sandra_id.txt', 'r') as f:
        result["sandra_id"] = f.read().strip()
except:
    pass

def find_elias_in_data(data):
    if isinstance(data, dict):
        items = data.get('visitors', data.get('users', []))
        if not items and 'firstName' in data: # it's a single item
            items = [data]
    elif isinstance(data, list):
        items = data
    else:
        return None
        
    for item in items:
        if isinstance(item, dict):
            if item.get("firstName") == "Elias" and item.get("lastName") == "Vance":
                return item
    return None

# Try Visitors API endpoint first
try:
    r_vis = s.get(f"{base}/visitors", timeout=5)
    if r_vis.status_code in (200, 201):
        elias = find_elias_in_data(r_vis.json())
        if elias:
            result["elias_target"] = elias
            result["api_source"] = "visitors"
except Exception as e:
    print(f"Visitors API check failed: {e}")

# If not found, try Users API endpoint
if not result["elias_target"]:
    try:
        r_user = s.get(f"{base}/users", timeout=5)
        if r_user.status_code in (200, 201):
            elias = find_elias_in_data(r_user.json())
            if elias:
                result["elias_target"] = elias
                result["api_source"] = "users"
    except Exception as e:
        print(f"Users API check failed: {e}")

# If Elias is found, try to fetch extended credentials info
if result["elias_target"]:
    uid = result["elias_target"].get("id") or result["elias_target"].get("userId")
    if uid:
        try:
            # Check credentials directly
            r_cred = s.get(f"{base}/users/{uid}/credentials", timeout=5)
            if r_cred.status_code == 200:
                result["elias_target"]["credentials_ext"] = r_cred.json()
        except:
            pass

# Save to json file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

python3 /tmp/export_data.py

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="