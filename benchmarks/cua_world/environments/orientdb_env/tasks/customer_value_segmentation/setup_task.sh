#!/bin/bash
echo "=== Setting up Customer Value Segmentation Task ==="

# Ensure safe PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 60

# --- DATA PREPARATION: Inject Tracer Accounts ---
# We inject specific accounts with known order values to verify the agent's logic perfectly.
# vip_tracer: 2000 + 1500 = 3500 (Platinum)
# mid_tracer: 1500 (Gold)
# low_tracer: 500 (Silver)
# inactive_tracer: 0 (Silver)

echo "Injecting tracer data..."
cat << EOF > /tmp/inject_tracers.py
import urllib.request
import json
import base64
import sys

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

def sql(command):
    req = urllib.request.Request(
        f"{BASE_URL}/command/demodb/sql",
        data=json.dumps({"command": command}).encode(),
        headers=HEADERS,
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except Exception as e:
        print(f"Error: {e}")
        return {}

# 1. Clean up potential leftovers
emails = ["vip_tracer@example.com", "mid_tracer@example.com", "low_tracer@example.com", "inactive_tracer@example.com"]
for email in emails:
    # Delete profile (cascade deletion of edges handled manually if needed, but simple DELETE VERTEX usually suffices)
    sql(f"DELETE VERTEX Profiles WHERE Email = '{email}'")

# 2. Create Profiles
tracers = [
    {"email": "vip_tracer@example.com", "name": "Victoria", "surname": "VIP", "orders": [2000, 1500]},
    {"email": "mid_tracer@example.com", "name": "Mike", "surname": "Mid", "orders": [1500]},
    {"email": "low_tracer@example.com", "name": "Larry", "surname": "Low", "orders": [500]},
    {"email": "inactive_tracer@example.com", "name": "Ian", "surname": "Inactive", "orders": []}
]

for t in tracers:
    # Insert Profile
    print(f"Creating profile for {t['email']}")
    res = sql(f"INSERT INTO Profiles SET Email='{t['email']}', Name='{t['name']}', Surname='{t['surname']}', Gender='Male'")
    if not res.get('result'):
        print(f"Failed to create profile {t['email']}")
        continue
    
    profile_rid = res['result'][0]['@rid']
    
    # Create Orders and Edges
    for price in t['orders']:
        # Insert Order
        ord_res = sql(f"INSERT INTO Orders SET Price={price}, Date='2023-01-01'")
        if ord_res.get('result'):
            order_rid = ord_res['result'][0]['@rid']
            # Link Profile -> Order
            sql(f"CREATE EDGE HasOrder FROM {profile_rid} TO {order_rid}")

print("Tracer data injection complete.")
EOF

python3 /tmp/inject_tracers.py

# Ensure Firefox is clean
kill_firefox

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
launch_firefox "http://localhost:2480/studio/index.html" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="