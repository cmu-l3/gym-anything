#!/bin/bash
set -e
echo "=== Setting up infer_favorite_destination task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 120

# Install python requests if not present (useful for the seeding script)
if ! python3 -c "import requests" 2>/dev/null; then
    pip3 install requests >/dev/null 2>&1 || true
fi

# Ensure data exists for the task
# We check if there are enough HasStayed edges. If not, we generate random ones.
cat > /tmp/seed_stays.py << 'EOF'
import json
import random
import sys
import base64
import urllib.request

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def sql(command):
    req = urllib.request.Request(
        f"{BASE_URL}/command/demodb/sql",
        data=json.dumps({"command": command}).encode(),
        headers=HEADERS,
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read()).get("result", [])
    except Exception as e:
        print(f"SQL Error: {e}", file=sys.stderr)
        return []

# Check existing edges
count_res = sql("SELECT count(*) as c FROM HasStayed")
count = count_res[0].get("c", 0) if count_res else 0
print(f"Current HasStayed count: {count}")

if count < 30:
    print("Seeding random stays...")
    profiles = sql("SELECT @rid FROM Profiles")
    hotels = sql("SELECT @rid FROM Hotels")
    
    if not profiles or not hotels:
        print("Error: Missing profiles or hotels!")
        sys.exit(1)
        
    # Generate 50 random stays
    for _ in range(50):
        p = random.choice(profiles)['@rid']
        h = random.choice(hotels)['@rid']
        # Use simple SQL to create edge
        sql(f"CREATE EDGE HasStayed FROM {p} TO {h}")
    print("Seeding complete.")
else:
    print("Sufficient data exists.")
EOF

python3 /tmp/seed_stays.py

# Clean up any previous 'FavoriteDestination' property if it exists (reset state)
# We accept failure here in case the property doesn't exist
orientdb_sql "demodb" "DROP PROPERTY Profiles.FavoriteDestination FORCE" >/dev/null 2>&1 || true

# Record initial edge count for anti-gaming verification
INITIAL_EDGES=$(orientdb_sql "demodb" "SELECT count(*) as c FROM HasStayed" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['result'][0]['c'])" 2>/dev/null || echo "0")
echo "$INITIAL_EDGES" > /tmp/initial_edge_count.txt

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="