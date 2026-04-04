#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting graph_pattern_detection results ==="
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot captured."

# 2. Check Report File
REPORT_PATH="/home/ga/travel_buddy_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    # Read first 50 lines of report to embed in JSON
    REPORT_CONTENT=$(head -n 50 "$REPORT_PATH" | base64 -w 0)
fi

# 3. Query OrientDB for verification metrics
# We execute a Python script to gather all DB metrics at once into a JSON structure
echo "Querying database state..."

cat > /tmp/query_metrics.py << 'EOF'
import sys
import json
import urllib.request
import base64

ROOT_PASS = "GymAnything123!"
BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(f"root:{ROOT_PASS}".encode()).decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

def run_sql(command):
    try:
        data = json.dumps({"command": command}).encode()
        req = urllib.request.Request(f"{BASE_URL}/command/demodb/sql", data=data, headers=HEADERS, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read()).get("result", [])
    except Exception as e:
        return []

def get_schema():
    try:
        req = urllib.request.Request(f"{BASE_URL}/database/demodb", headers=HEADERS, method="GET")
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except:
        return {}

metrics = {}

# Check Class Schema
schema = get_schema()
classes = {c['name']: c for c in schema.get('classes', [])}
metrics['class_exists'] = 'TravelBuddy' in classes
metrics['class_extends_e'] = 'E' in classes.get('TravelBuddy', {}).get('superClass', '') or 'E' in classes.get('TravelBuddy', {}).get('superClasses', [])
metrics['property_exists'] = False
if metrics['class_exists']:
    props = {p['name']: p for p in classes['TravelBuddy'].get('properties', [])}
    metrics['property_exists'] = 'SharedHotels' in props
    metrics['property_type'] = props.get('SharedHotels', {}).get('type', 'UNKNOWN')

# Check Edge Count
res = run_sql("SELECT COUNT(*) as cnt FROM TravelBuddy")
metrics['edge_count'] = res[0].get('cnt', 0) if res else 0

# Check Total SharedHotels Sum
res = run_sql("SELECT SUM(SharedHotels) as total FROM TravelBuddy")
metrics['shared_hotels_sum'] = res[0].get('total', 0) if res else 0

# Spot Check 1: John Smith <-> David Jones
# Query looks for edges between these two emails
q1 = "SELECT SharedHotels FROM TravelBuddy WHERE (out.Email='john.smith@example.com' AND in.Email='david.jones@example.com') OR (in.Email='john.smith@example.com' AND out.Email='david.jones@example.com')"
res = run_sql(q1)
metrics['john_david_shared'] = res[0].get('SharedHotels', 0) if res else 0

# Spot Check 2: Maria Garcia <-> Luca Rossi
q2 = "SELECT SharedHotels FROM TravelBuddy WHERE (out.Email='maria.garcia@example.com' AND in.Email='luca.rossi@example.com') OR (in.Email='maria.garcia@example.com' AND out.Email='luca.rossi@example.com')"
res = run_sql(q2)
metrics['maria_luca_shared'] = res[0].get('SharedHotels', 0) if res else 0

# Check for self-loops or duplicates
res = run_sql("SELECT COUNT(*) as cnt FROM TravelBuddy WHERE out = in")
metrics['self_loops'] = res[0].get('cnt', 0) if res else 0

print(json.dumps(metrics))
EOF

# Run the python script and capture output
DB_METRICS=$(python3 /tmp/query_metrics.py 2>/dev/null || echo "{}")

# 4. Construct Final JSON
# Use jq to merge robustly if available, else simple cat
# We'll use a python script to merge to avoid jq dependency issues
cat > /tmp/merge_json.py << EOF
import json
import sys

try:
    db_metrics = json.loads('${DB_METRICS}')
except:
    db_metrics = {}

result = {
    "task_start": ${TASK_START},
    "task_end": ${TASK_END},
    "report_exists": ${REPORT_EXISTS},
    "report_mtime": ${REPORT_MTIME},
    "report_content_b64": "${REPORT_CONTENT}",
    "db_metrics": db_metrics
}
print(json.dumps(result, indent=2))
EOF

python3 /tmp/merge_json.py > /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="