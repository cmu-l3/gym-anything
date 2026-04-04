#!/bin/bash
echo "=== Setting up class_hierarchy_refactor task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 120

# 1. Clean up any previous attempts (Idempotency)
echo "Cleaning up previous schema changes..."
orientdb_sql demodb "DROP CLASS BudgetHotels UNSAFE" > /dev/null 2>&1 || true
orientdb_sql demodb "DROP CLASS MidRangeHotels UNSAFE" > /dev/null 2>&1 || true
orientdb_sql demodb "DROP CLASS LuxuryHotels UNSAFE" > /dev/null 2>&1 || true
orientdb_sql demodb "DROP PROPERTY Hotels.Tier FORCE" > /dev/null 2>&1 || true

# 2. Ensure data distribution allows for all 3 classes to have records
# We need at least one record in each Star category (<=2, 3, >=4)
echo "Adjusting data distribution..."

# Reset some stars to ensure deterministic starting state
orientdb_sql demodb "UPDATE Hotels SET Stars = 4 WHERE Name = 'Hotel Artemide'"
orientdb_sql demodb "UPDATE Hotels SET Stars = 5 WHERE Name = 'Hotel Adlon Kempinski'"
orientdb_sql demodb "UPDATE Hotels SET Stars = 3 WHERE Name = 'The Savoy'"
orientdb_sql demodb "UPDATE Hotels SET Stars = 2 WHERE Name = 'Hotel de Crillon'" 
orientdb_sql demodb "UPDATE Hotels SET Stars = 1 WHERE Name LIKE '%Motel%'"

# 3. Calculate and record EXPECTED counts for verification
# This tells us how many records SHOULD end up in each class if the user follows instructions
echo "Calculating expected migration counts..."

cat > /tmp/calc_expected.py << 'PYEOF'
import sys, json
import urllib.request, base64

def query(sql):
    auth = base64.b64encode(b"root:GymAnything123!").decode()
    req = urllib.request.Request(
        "http://localhost:2480/command/demodb/sql",
        data=json.dumps({"command": sql}).encode(),
        headers={"Authorization": f"Basic {auth}", "Content-Type": "application/json"},
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read()).get('result', [{}])[0].get('cnt', 0)
    except:
        return 0

total = query("SELECT COUNT(*) as cnt FROM Hotels")
budget = query("SELECT COUNT(*) as cnt FROM Hotels WHERE Stars <= 2")
mid = query("SELECT COUNT(*) as cnt FROM Hotels WHERE Stars = 3")
luxury = query("SELECT COUNT(*) as cnt FROM Hotels WHERE Stars >= 4")

result = {
    "expected_total": total,
    "expected_budget": budget,
    "expected_midrange": mid,
    "expected_luxury": luxury
}

with open("/tmp/expected_counts.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result))
PYEOF

python3 /tmp/calc_expected.py

# 4. Remove report file if exists
rm -f /home/ga/hotel_hierarchy_report.txt

# 5. Launch Firefox to Studio
echo "Launching Firefox..."
kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 10

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="