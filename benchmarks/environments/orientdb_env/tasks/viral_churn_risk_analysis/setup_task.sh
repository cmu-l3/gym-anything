#!/bin/bash
set -e
echo "=== Setting up Viral Churn Risk Analysis Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# Python script to seed the specific scenario
cat > /tmp/seed_viral_scenario.py << 'EOF'
import sys
import json
import base64
import urllib.request

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
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        print(f"SQL Error: {e.read().decode()}")
        return {}
    except Exception as e:
        print(f"Error: {e}")
        return {}

print("Seeding scenario...")

# 1. Ensure Tickets class exists
sql("CREATE CLASS Tickets EXTENDS V")
sql("CREATE PROPERTY Tickets.email STRING")
sql("CREATE PROPERTY Tickets.severity STRING")
sql("CREATE PROPERTY Tickets.subject STRING")

# 2. Clean slate for specific entities
sql("DELETE VERTEX Tickets")
# Clean existing HasFriend edges between our test subjects to avoid duplicates/confusion
# RIDs will be looked up dynamically
emails = [
    "john.smith@example.com",
    "maria.garcia@example.com",
    "david.jones@example.com",
    "sophie.martin@example.com"
]
for e in emails:
    # Remove ChurnRisk property if it exists from previous run
    sql(f"UPDATE Profiles REMOVE ChurnRisk WHERE Email = '{e}'")

# Helper to get RID
def get_rid(email):
    res = sql(f"SELECT @rid FROM Profiles WHERE Email = '{email}'")
    rows = res.get("result", [])
    if rows:
        return rows[0].get("@rid")
    return None

john = get_rid("john.smith@example.com")
maria = get_rid("maria.garcia@example.com")
david = get_rid("david.jones@example.com")
sophie = get_rid("sophie.martin@example.com")

if not all([john, maria, david, sophie]):
    print("FATAL: One or more test profiles missing. Run base seed_demodb.py first.")
    sys.exit(1)

# 3. Clean edges between these specific nodes
sql(f"DELETE EDGE HasFriend WHERE (out = {john} OR in = {john})")
sql(f"DELETE EDGE HasFriend WHERE (out = {maria} OR in = {maria})")
sql(f"DELETE EDGE HasFriend WHERE (out = {david} OR in = {david})")
sql(f"DELETE EDGE HasFriend WHERE (out = {sophie} OR in = {sophie})")

# 4. Insert Tickets (Unlinked)
# John -> High Severity
sql(f"INSERT INTO Tickets SET email='john.smith@example.com', severity='High', subject='System Crash'")
# David -> Low Severity
sql(f"INSERT INTO Tickets SET email='david.jones@example.com', severity='Low', subject='Typo in UI'")

# 5. Create Friendships
# John (High) --friend--> Maria (Should become Risk)
sql(f"CREATE EDGE HasFriend FROM {john} TO {maria}")

# David (Low) --friend--> Sophie (Should NOT become Risk)
sql(f"CREATE EDGE HasFriend FROM {david} TO {sophie}")

print("Seeding complete.")
EOF

# Run seeder
python3 /tmp/seed_viral_scenario.py

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile 'http://localhost:2480/studio/index.html' &"
sleep 8

# Maximize and focus
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="