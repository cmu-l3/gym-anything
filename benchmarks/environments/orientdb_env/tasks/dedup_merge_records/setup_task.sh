#!/bin/bash
set -e
echo "=== Setting up Data Deduplication Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# Create the python script to inject duplicates
cat > /tmp/inject_duplicates.py << 'PYEOF'
import urllib.request
import json
import base64
import sys
import time

# Configuration
BASE_URL = "http://localhost:2480"
# Admin credentials for DB operations
AUTH = base64.b64encode(b"admin:admin").decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def sql(command):
    data = json.dumps({"command": command}).encode()
    req = urllib.request.Request(
        f"{BASE_URL}/command/demodb/sql",
        data=data, headers=HEADERS, method="POST"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except Exception as e:
        print(f"SQL Error: {e}")
        return {"result": []}

def get_rid(query):
    res = sql(query)
    return res['result'][0]['@rid'] if res.get('result') else None

print("Injecting duplicates...")

# 1. Drop the unique index to allow duplicates
sql("DROP INDEX Profiles.Email")
print("Dropped Profiles.Email index")

# 2. Get RIDs of originals to link FROM/TO
# We need specific people to have edges to the duplicates to verify transfer later
luca_rid = get_rid("SELECT @rid FROM Profiles WHERE Email='luca.rossi@example.com'")
anna_rid = get_rid("SELECT @rid FROM Profiles WHERE Email='anna.mueller@example.com'")
james_rid = get_rid("SELECT @rid FROM Profiles WHERE Email='james.brown@example.com'")
emma_rid = get_rid("SELECT @rid FROM Profiles WHERE Email='emma.white@example.com'")
carlos_rid = get_rid("SELECT @rid FROM Profiles WHERE Email='carlos.lopez@example.com'")

if not all([luca_rid, anna_rid, james_rid, emma_rid, carlos_rid]):
    print("Error: Could not find required original profiles")
    sys.exit(1)

# 3. Create Duplicate Hotels
# Dup 1: Hotel Artemide (Rome) - Original has edges, we add new ones to dup
res = sql("INSERT INTO Hotels SET Name='Hotel Artemide', City='Rome', Stars=4, Type='Duplicate', Street='Via Nazionale 22b'")
h_dup1 = res['result'][0]['@rid']
# Add edges to this dup
sql(f"CREATE EDGE HasStayed FROM {luca_rid} TO {h_dup1}")
sql(f"CREATE EDGE HasStayed FROM {anna_rid} TO {h_dup1}")

# Dup 2: The Savoy (London)
res = sql("INSERT INTO Hotels SET Name='The Savoy', City='London', Stars=5, Type='Duplicate', Street='The Strand B'")
h_dup2 = res['result'][0]['@rid']
sql(f"CREATE EDGE HasStayed FROM {james_rid} TO {h_dup2}")

# Dup 3: Copacabana Palace (Rio)
res = sql("INSERT INTO Hotels SET Name='Copacabana Palace', City='Rio de Janeiro', Stars=5, Type='Duplicate'")
h_dup3 = res['result'][0]['@rid']
sql(f"CREATE EDGE HasStayed FROM {emma_rid} TO {h_dup3}")

# 4. Create Duplicate Profiles
# Dup 1: John Smith
res = sql("INSERT INTO Profiles SET Name='John', Surname='Smith', Email='john.smith@example.com', Type='Duplicate'")
p_dup1 = res['result'][0]['@rid']
# Edge TO duplicate
sql(f"CREATE EDGE HasFriend FROM {carlos_rid} TO {p_dup1}")

# Dup 2: Yuki Tanaka
res = sql("INSERT INTO Profiles SET Name='Yuki', Surname='Tanaka', Email='yuki.tanaka@example.com', Type='Duplicate'")
p_dup2 = res['result'][0]['@rid']
# Edge TO duplicate
sql(f"CREATE EDGE HasFriend FROM {emma_rid} TO {p_dup2}")
# Edge FROM duplicate
sql(f"CREATE EDGE HasFriend FROM {p_dup2} TO {james_rid}")

print("Injection complete. 3 Hotel dups, 2 Profile dups, 7 edges created.")
PYEOF

# Run the injection script
echo "Running injection script..."
python3 /tmp/inject_duplicates.py

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html' &"
sleep 10

# Maximize
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial counts for setup verification
HOTEL_COUNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Hotels" | grep -oE '[0-9]+' | tail -1)
echo "$HOTEL_COUNT" > /tmp/initial_hotel_count.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="