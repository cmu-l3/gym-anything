#!/bin/bash
echo "=== Exporting Ingest Conference Schedule Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
JSON_MTIME=$(stat -c %Y /home/ga/conference_data.json 2>/dev/null || echo "0")
FILE_ACCESSED="false"
# If atime > start time, file was read (rough check)
JSON_ATIME=$(stat -c %X /home/ga/conference_data.json 2>/dev/null || echo "0")
if [ "$JSON_ATIME" -gt "$TASK_START" ]; then
    FILE_ACCESSED="true"
fi

# 3. Query Database State using Python
# We run this inside the container to access localhost:2480 easily
cat > /tmp/audit_db.py << 'EOF'
import json
import base64
import urllib.request
import sys

URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

def sql(command):
    try:
        req = urllib.request.Request(
            f"{URL}/command/demodb/sql",
            data=json.dumps({"command": command}).encode(),
            headers=HEADERS,
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read()).get("result", [])
    except Exception as e:
        return []

def get_schema():
    try:
        req = urllib.request.Request(f"{URL}/database/demodb", headers=HEADERS, method="GET")
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.loads(r.read())
            return [c["name"] for c in data.get("classes", [])]
    except:
        return []

results = {
    "schema": [],
    "counts": {"Conferences": 0, "Sessions": 0},
    "edges": {
        "HostedAt": 0,
        "HasSession": 0,
        "PresentedBy": 0
    },
    "topology": {
        "conf_hotel_links": [],
        "session_speaker_links": []
    }
}

# 1. Check Schema
results["schema"] = get_schema()

# 2. Check Counts
if "Conferences" in results["schema"]:
    res = sql("SELECT count(*) as c FROM Conferences")
    results["counts"]["Conferences"] = res[0].get("c", 0) if res else 0

if "Sessions" in results["schema"]:
    res = sql("SELECT count(*) as c FROM Sessions")
    results["counts"]["Sessions"] = res[0].get("c", 0) if res else 0

# 3. Check Edges
for edge in ["HostedAt", "HasSession", "PresentedBy"]:
    if edge in results["schema"]:
        res = sql(f"SELECT count(*) as c FROM {edge}")
        results["edges"][edge] = res[0].get("c", 0) if res else 0

# 4. Check Topology Details
# Check Conference -> Hotel links
if "HostedAt" in results["schema"] and "Conferences" in results["schema"]:
    # Select Conference Name and Hotel Name
    q = "SELECT Name, out('HostedAt').Name as HotelName FROM Conferences"
    rows = sql(q)
    for r in rows:
        c_name = r.get("Name")
        h_name = r.get("HotelName")
        # Handle single value or list
        if isinstance(h_name, list) and h_name: h_name = h_name[0]
        results["topology"]["conf_hotel_links"].append({"conf": c_name, "hotel": h_name})

# Check Session -> Speaker links
if "PresentedBy" in results["schema"] and "Sessions" in results["schema"]:
    q = "SELECT Title, out('PresentedBy').Email as SpeakerEmail FROM Sessions"
    rows = sql(q)
    for r in rows:
        s_title = r.get("Title")
        email = r.get("SpeakerEmail")
        if isinstance(email, list) and email: email = email[0]
        results["topology"]["session_speaker_links"].append({"session": s_title, "email": email})

print(json.dumps(results))
EOF

echo "Running DB audit..."
python3 /tmp/audit_db.py > /tmp/db_state.json 2>/dev/null || echo "{}" > /tmp/db_state.json

# 4. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_accessed": $FILE_ACCESSED,
    "screenshot_path": "/tmp/task_final.png",
    "db_state": $(cat /tmp/db_state.json)
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json