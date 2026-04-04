#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# We need to export the database state to a JSON file for the verifier to check.
# The verifier needs:
# 1. The Profiles schema (to check if FavoriteDestination exists)
# 2. The Profiles data (RID + FavoriteDestination value)
# 3. The Graph structure (HasStayed edges + Hotel Countries) to compute ground truth
# We'll do this via a Python script that queries the API and dumps a JSON.

cat > /tmp/export_data.py << 'EOF'
import json
import sys
import base64
import urllib.request

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def get_api(path):
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        headers=HEADERS,
        method="GET"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {}

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
        return []

data = {}

# 1. Get Schema
db_info = get_api("/database/demodb")
classes = {c['name']: c for c in db_info.get('classes', [])}
profiles_schema = classes.get('Profiles', {})
data['profiles_schema'] = {
    'properties': profiles_schema.get('properties', [])
}

# 2. Get Profiles Data
# We select RID and the new property. 
# We fetch ALL properties to be safe, but focus on FavoriteDestination
profiles = sql("SELECT @rid, FavoriteDestination FROM Profiles")
data['profiles'] = profiles

# 3. Get Ground Truth Data Components
# We need to reconstruct the visits to calculate the expected favorite.
# Fetch all edges: out(Profile) -> in(Hotel)
edges = sql("SELECT out, in FROM HasStayed")
data['edges'] = edges

# Fetch all hotels: RID -> Country
hotels = sql("SELECT @rid, Country FROM Hotels")
data['hotels'] = hotels

# 4. Anti-gaming: Current edge count
data['edge_count'] = len(edges)

# Save to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
EOF

# Execute the export script
python3 /tmp/export_data.py

# Add metadata to the JSON (timestamps, etc) using jq or temp file manipulation
# Since jq might not be available or robust, we'll append using python
python3 -c "
import json
try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except:
    data = {}

data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
data['initial_edge_count'] = $(cat /tmp/initial_edge_count.txt 2>/dev/null || echo 0)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="