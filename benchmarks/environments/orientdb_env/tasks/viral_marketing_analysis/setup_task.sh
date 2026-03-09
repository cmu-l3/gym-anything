#!/bin/bash
set -e
echo "=== Setting up Viral Marketing Task ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# Source OrientDB utilities
source /workspace/scripts/task_utils.sh

# Ensure OrientDB is running
wait_for_orientdb 60

# Create the data injection script
cat > /tmp/inject_marketing_data.py << 'EOF'
import sys
import json
import base64
import urllib.request
import time

BASE_URL = "http://localhost:2480"
AUTH = "Basic " + base64.b64encode(b"root:GymAnything123!").decode("utf-8")
HEADERS = {"Authorization": AUTH, "Content-Type": "application/json"}

def sql(command):
    req = urllib.request.Request(f"{BASE_URL}/command/demodb/sql", 
                                 data=json.dumps({"command": command}).encode(), 
                                 headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except Exception as e:
        print(f"SQL Error: {e}")
        return {}

def create_profile(name, email):
    # Check if exists first to avoid duplicates on re-run
    check = sql(f"SELECT FROM Profiles WHERE Email='{email}'")
    if check.get('result'):
        return check['result'][0]['@rid']
    
    res = sql(f"INSERT INTO Profiles SET Name='{name}', Email='{email}', Surname='Test', Nationality='UK'")
    if 'result' in res and len(res['result']) > 0:
        return res['result'][0]['@rid']
    return None

def create_order(price):
    res = sql(f"INSERT INTO Orders SET Price={price}, Date='2023-01-01', Status='Completed'")
    if 'result' in res and len(res['result']) > 0:
        return res['result'][0]['@rid']
    return None

def link_friend(p1_rid, p2_rid):
    sql(f"CREATE EDGE HasFriend FROM {p1_rid} TO {p2_rid}")

def link_order(p_rid, o_rid):
    sql(f"CREATE EDGE HasOrder FROM {p_rid} TO {o_rid}")

print("Injecting Marketing Data...")

# Case A: The Hub (Liam) - High Network Value ($1750), 3 Friends
# Friends: Noel ($1000), Gem ($500), Andy ($250)
liam = create_profile("Liam", "liam.hub@test.com")
friends_a_data = [("Noel", 1000), ("Gem", 500), ("Andy", 250)]
for name, price in friends_a_data:
    fid = create_profile(name, f"{name.lower()}@test.com")
    link_friend(liam, fid)
    oid = create_order(price)
    link_order(fid, oid)

# Case B: Damon (The Popular) - High Connections (5), Low Value ($50 total)
damon = create_profile("Damon", "damon.pop@test.com")
for i in range(5):
    fid = create_profile(f"Fan{i}", f"fan{i}@test.com")
    link_friend(damon, fid)
    oid = create_order(10.0)
    link_order(fid, oid)

# Case C: Graham (The Loner) - Zero Connections, High Personal Spend
graham = create_profile("Graham", "graham.solo@test.com")
oid_personal = create_order(5000.0)
link_order(graham, oid_personal)

print("Injection Complete.")
EOF

# Run data injection
echo "Injecting dataset..."
python3 /tmp/inject_marketing_data.py

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile 'http://localhost:2480/studio/index.html' &"

# Wait for window and maximize
sleep 8
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="