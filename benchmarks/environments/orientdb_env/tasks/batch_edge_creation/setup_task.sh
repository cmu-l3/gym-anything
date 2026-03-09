#!/bin/bash
set -e
echo "=== Setting up batch_edge_creation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# 1. Clean up any previous state (Idempotency)
echo "Cleaning up previous 'IsNearby' class if exists..."
# Attempt to delete edges and drop class. Suppress errors if class doesn't exist.
orientdb_sql "demodb" "DELETE EDGE IsNearby" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS IsNearby UNSAFE" > /dev/null 2>&1 || true

# 2. Verify Data Requirements (Hotels and Restaurants must exist)
echo "Verifying demodb data..."
HOTEL_COUNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Hotels" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
REST_COUNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Restaurants" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

echo "  Hotels: $HOTEL_COUNT"
echo "  Restaurants: $REST_COUNT"

if [ "$HOTEL_COUNT" -eq "0" ] || [ "$REST_COUNT" -eq "0" ]; then
    echo "ERROR: Database missing required data. Attempting to seed..."
    /workspace/scripts/setup_orientdb.sh
fi

# 3. Calculate Expected Edge Count
# We need to know exactly how many edges SHOULD be created to verify correctness.
# Logic: Sum(Hotels_in_City_X * Restaurants_in_City_X) for all cities.
echo "Calculating expected edge count..."
cat > /tmp/calc_expected.py << 'EOF'
import sys, json, urllib.request, base64

def sql(cmd):
    auth = base64.b64encode(b"root:GymAnything123!").decode()
    req = urllib.request.Request(
        "http://localhost:2480/command/demodb/sql",
        data=json.dumps({"command": cmd}).encode(),
        headers={"Authorization": f"Basic {auth}", "Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())

hotels = sql("SELECT City, count(*) as cnt FROM Hotels GROUP BY City")
rests = sql("SELECT City, count(*) as cnt FROM Restaurants GROUP BY City")

h_map = {r['City']: r['cnt'] for r in hotels.get('result', [])}
r_map = {r['City']: r['cnt'] for r in rests.get('result', [])}

total_edges = 0
for city, h_count in h_map.items():
    if city in r_map:
        total_edges += h_count * r_map[city]

print(total_edges)
EOF

EXPECTED_EDGES=$(python3 /tmp/calc_expected.py 2>/dev/null || echo "0")
echo "$EXPECTED_EDGES" > /tmp/expected_edge_count.txt
echo "Expected edges: $EXPECTED_EDGES"

# 4. Prepare Application State
echo "Launching Firefox..."
kill_firefox
# Start Firefox pointing to Studio
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html' &"
sleep 8

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="