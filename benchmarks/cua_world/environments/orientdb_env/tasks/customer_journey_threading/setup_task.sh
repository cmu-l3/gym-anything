#!/bin/bash
set -e

echo "=== Setting up Customer Journey Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# Clean up any previous run artifacts (schema and data)
echo "Cleaning up previous state..."
orientdb_sql "demodb" "DELETE VERTEX TimelineEvent" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS TimelineEvent" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS NextEvent" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS StartsJourney" >/dev/null 2>&1 || true

# Remove specific test profile if exists to ensure fresh data injection
orientdb_sql "demodb" "DELETE VERTEX Profiles WHERE Email='sofia.ricci@journey.com'" >/dev/null 2>&1 || true

# Inject specific scenario data using Python
echo "Injecting scenario data for sofia.ricci@journey.com..."
python3 -c '
import sys
import json
import base64
import urllib.request
import time

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

def sql(cmd):
    req = urllib.request.Request(f"{BASE_URL}/command/demodb/sql", data=json.dumps({"command": cmd}).encode(), headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except Exception as e:
        print(f"Error executing {cmd}: {e}")
        return {}

# 1. Create Profile
print("  Creating Profile...")
p_res = sql("INSERT INTO Profiles SET Email=\"sofia.ricci@journey.com\", Name=\"Sofia\", Surname=\"Ricci\", Nationality=\"Italian\"")
p_rid = p_res.get("result", [{}])[0].get("@rid")
if not p_rid:
    # Try to find it if insert failed (maybe race condition)
    p_res = sql("SELECT @rid FROM Profiles WHERE Email=\"sofia.ricci@journey.com\"")
    p_rid = p_res.get("result", [{}])[0].get("@rid")

if not p_rid:
    print("  FATAL: Could not create/find profile")
    sys.exit(1)

print(f"  Profile RID: {p_rid}")

# 2. Create Orders (Order -> HasCustomer -> Profile)
# Order 1: Jan 10, 2023
o1_res = sql("INSERT INTO Orders SET OrderedId=1001, Date=\"2023-01-10\", Status=\"Completed\", Price=450.00")
o1_rid = o1_res.get("result", [{}])[0].get("@rid")
sql(f"CREATE EDGE HasCustomer FROM {o1_rid} TO {p_rid}")

# Order 2: June 20, 2023
o2_res = sql("INSERT INTO Orders SET OrderedId=1002, Date=\"2023-06-20\", Status=\"Pending\", Price=120.50")
o2_rid = o2_res.get("result", [{}])[0].get("@rid")
sql(f"CREATE EDGE HasCustomer FROM {o2_rid} TO {p_rid}")

# 3. Create Reviews (Profile -> MadeReview -> Review)
# Review 1: March 15, 2023
r1_res = sql("INSERT INTO Reviews SET Stars=5, Text=\"Lovely stay!\", Date=\"2023-03-15\"")
r1_rid = r1_res.get("result", [{}])[0].get("@rid")
sql(f"CREATE EDGE MadeReview FROM {p_rid} TO {r1_rid}")

# Review 2: July 01, 2023
r2_res = sql("INSERT INTO Reviews SET Stars=3, Text=\"Okay but noisy\", Date=\"2023-07-01\"")
r2_rid = r2_res.get("result", [{}])[0].get("@rid")
sql(f"CREATE EDGE MadeReview FROM {p_rid} TO {r2_rid}")

print("  Data injection complete.")
'

# Ensure Firefox is at OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="