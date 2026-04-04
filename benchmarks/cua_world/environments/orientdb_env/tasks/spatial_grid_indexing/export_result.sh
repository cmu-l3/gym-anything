#!/bin/bash
echo "=== Exporting Spatial Grid Indexing Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/zone_density_report.txt"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read first 10 lines of report
    REPORT_CONTENT=$(head -n 10 "$REPORT_PATH" | base64 -w 0)
fi

# 3. Query OrientDB Database State
# We use python inside the container to query the REST API and structure the data
# because complex JSON parsing in bash is error-prone.

cat > /tmp/inspect_db.py << 'EOF'
import sys
import json
import urllib.request
import base64

ROOT_PASS = "GymAnything123!"
BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(f"root:{ROOT_PASS}".encode()).decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def sql_query(command):
    try:
        data = json.dumps({"command": command}).encode()
        req = urllib.request.Request(
            f"{BASE_URL}/command/demodb/sql",
            data=data,
            headers=HEADERS,
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e), "result": []}

def get_schema():
    try:
        req = urllib.request.Request(
            f"{BASE_URL}/database/demodb",
            headers=HEADERS,
            method="GET"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

result = {}

# Check Schema
schema = get_schema()
classes = {c['name']: c for c in schema.get('classes', [])}
result['has_zone_class'] = 'GeographicZone' in classes
result['has_inzone_class'] = 'InZone' in classes
result['zone_extends_v'] = False
result['inzone_extends_e'] = False
result['has_unique_index'] = False

if result['has_zone_class']:
    cls = classes['GeographicZone']
    supers = cls.get('superClasses', []) or [cls.get('superClass', '')]
    if 'V' in supers:
        result['zone_extends_v'] = True
    
    # Check index
    indexes = cls.get('indexes', [])
    for idx in indexes:
        if idx['type'] == 'UNIQUE' and ('ZoneID' in idx.get('fields', []) or idx['name'].endswith('.ZoneID')):
            result['has_unique_index'] = True

if result['has_inzone_class']:
    cls = classes['InZone']
    supers = cls.get('superClasses', []) or [cls.get('superClass', '')]
    if 'E' in supers:
        result['inzone_extends_e'] = True

# Check Data Counts
res_z = sql_query("SELECT COUNT(*) as cnt FROM GeographicZone")
result['zone_count'] = res_z.get('result', [{}])[0].get('cnt', 0)

res_e = sql_query("SELECT COUNT(*) as cnt FROM InZone")
result['edge_count'] = res_e.get('result', [{}])[0].get('cnt', 0)

res_h = sql_query("SELECT COUNT(*) as cnt FROM Hotels")
result['hotel_count'] = res_h.get('result', [{}])[0].get('cnt', 0)

# Check Specific Links (Accuracy)
# Check Hotel Artemide (41.89, 12.49 -> 41_12)
q1 = "SELECT in.ZoneID as ZoneID FROM InZone WHERE out.Name = 'Hotel Artemide'"
r1 = sql_query(q1)
result['artemide_zone'] = r1.get('result', [{}])[0].get('ZoneID', None) if r1.get('result') else None

# Check Four Seasons Sydney (-33.86, 151.21 -> -33_151)
q2 = "SELECT in.ZoneID as ZoneID FROM InZone WHERE out.Name = 'Four Seasons Sydney'"
r2 = sql_query(q2)
result['sydney_zone'] = r2.get('result', [{}])[0].get('ZoneID', None) if r2.get('result') else None

print(json.dumps(result))
EOF

DB_STATE=$(python3 /tmp/inspect_db.py)

# 4. Construct Final JSON
# Use jq if available, otherwise python construction
python3 -c "
import json
import sys

db_state = json.loads('''$DB_STATE''')
report_content = '''$REPORT_CONTENT'''

output = {
    'task_start': $TASK_START,
    'report_exists': '$REPORT_EXISTS' == 'true',
    'report_created_during_task': '$REPORT_CREATED_DURING_TASK' == 'true',
    'report_content_b64': report_content,
    'db_state': db_state,
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(output, indent=2))
" > /tmp/task_result.json

# Cleanup
rm -f /tmp/inspect_db.py

# Move to accessible location
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json