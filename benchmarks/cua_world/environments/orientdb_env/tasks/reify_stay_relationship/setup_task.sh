#!/bin/bash
set -e
echo "=== Setting up reify_stay_relationship task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# Ensure demodb exists
if ! orientdb_db_exists "demodb"; then
    echo "Creating demodb..."
    /workspace/scripts/setup_orientdb.sh
fi

# Prepare Data: Ensure sufficient HasStayed edges exist for the migration to be meaningful
echo "Checking edge counts..."
python3 -c '
import requests, json, random, sys

AUTH = ("root", "GymAnything123!")
URL = "http://localhost:2480/command/demodb/sql"
HEADERS = {"Content-Type": "application/json"}

def sql(cmd):
    try:
        resp = requests.post(URL, json={"command": cmd}, auth=AUTH, headers=HEADERS)
        return resp.json().get("result", [])
    except Exception as e:
        print(f"Error: {e}")
        return []

# Check existing edges
res = sql("SELECT count(*) as c FROM HasStayed")
count = res[0].get("c", 0) if res else 0
print(f"Current HasStayed count: {count}")

# If too few, inject random edges
target = 50
if count < target:
    needed = target - count
    print(f"Seeding {needed} more edges...")
    profiles = [p["@rid"] for p in sql("SELECT @rid FROM Profiles")]
    hotels = [h["@rid"] for h in sql("SELECT @rid FROM Hotels")]
    
    if profiles and hotels:
        for _ in range(needed):
            p = random.choice(profiles)
            h = random.choice(hotels)
            sql(f"CREATE EDGE HasStayed FROM {p} TO {h}")
        print("Seeding complete.")
    else:
        print("Error: Profiles or Hotels missing.")

# Get Final Initial Count for verification
res_final = sql("SELECT count(*) as c FROM HasStayed")
final_count = res_final[0].get("c", 0) if res_final else 0

state = {
    "initial_has_stayed_count": final_count,
    "timestamp": "initial"
}

with open("/tmp/initial_state.json", "w") as f:
    json.dump(state, f)
    
print(f"Task prepared with {final_count} edges to migrate.")
'

# Clean up any partial attempts from previous runs (if environment was reused)
echo "Cleaning up any partial previous attempts..."
orientdb_sql "demodb" "DELETE VERTEX StaySession" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS StaySession UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS HasSession UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS SessionAt UNSAFE" > /dev/null 2>&1 || true

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="