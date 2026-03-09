#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Collect Database State via Python script
# We export the schema and data counts to a JSON file for the verifier
echo "Querying database state..."
python3 -c '
import urllib.request
import json
import base64
import sys

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def get_json(url):
    req = urllib.request.Request(url, headers=HEADERS, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception:
        return {}

def post_sql(db, command):
    data = json.dumps({"command": command}).encode()
    req = urllib.request.Request(
        f"{BASE_URL}/command/{db}/sql",
        data=data,
        headers=HEADERS,
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception:
        return {}

result = {
    "amenity_class_exists": False,
    "hasamenity_class_exists": False,
    "amenity_name_unique": False,
    "amenities_property_exists": False,
    "amenity_count": 0,
    "edge_count": 0,
    "plaza_amenities": []
}

# 1. Check Schema
db_info = get_json(f"{BASE_URL}/database/demodb")
classes = {c["name"]: c for c in db_info.get("classes", [])}

if "Amenity" in classes:
    result["amenity_class_exists"] = True
    # Check index
    indexes = classes["Amenity"].get("indexes", [])
    for idx in indexes:
        if "Name" in idx.get("fields", []) and idx.get("type") == "UNIQUE":
            result["amenity_name_unique"] = True

if "HasAmenity" in classes:
    result["hasamenity_class_exists"] = True

if "Hotels" in classes:
    props = {p["name"] for p in classes["Hotels"].get("properties", [])}
    if "Amenities" in props:
        result["amenities_property_exists"] = True

# 2. Check Counts
if result["amenity_class_exists"]:
    res = post_sql("demodb", "SELECT count(*) as cnt FROM Amenity")
    result["amenity_count"] = res.get("result", [{}])[0].get("cnt", 0)

if result["hasamenity_class_exists"]:
    res = post_sql("demodb", "SELECT count(*) as cnt FROM HasAmenity")
    result["edge_count"] = res.get("result", [{}])[0].get("cnt", 0)

# 3. Specific Hotel Check
# Get amenities for The Plaza Hotel via graph traversal
# SELECT out("HasAmenity").Name FROM Hotels WHERE Name="The Plaza Hotel"
res = post_sql("demodb", "SELECT out(\"HasAmenity\").Name as ams FROM Hotels WHERE Name=\"The Plaza Hotel\"")
data = res.get("result", [])
if data:
    # OrientDB returns this as a list of lists or flattened depending on version/query
    # Usually [ { "ams": ["WiFi", "Gym"] } ]
    raw_ams = data[0].get("ams", [])
    if raw_ams:
        result["plaza_amenities"] = sorted(raw_ams)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
'

# Set permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="