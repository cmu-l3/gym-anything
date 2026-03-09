#!/bin/bash
set -e
echo "=== Exporting import_csv_data task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We need to query the database state and save it to a JSON file
# Using Python for robust API interaction and JSON generation
python3 -c '
import sys
import json
import urllib.request
import base64

# Configuration
BASE_URL = "http://localhost:2480"
DB = "demodb"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def sql_query(command):
    try:
        req = urllib.request.Request(
            f"{BASE_URL}/command/{DB}/sql",
            data=json.dumps({"command": command}).encode(),
            headers=HEADERS,
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"result": [], "error": str(e)}

def get_schema():
    try:
        req = urllib.request.Request(
            f"{BASE_URL}/database/{DB}",
            headers=HEADERS,
            method="GET"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"classes": [], "error": str(e)}

# 1. Get Schema Information (Classes, Properties, Indexes)
schema = get_schema()
classes = {c["name"]: c for c in schema.get("classes", [])}

airports_class = classes.get("Airports", {})
edge_class = classes.get("IsInCountry", {})

# 2. Get Record Counts
airports_count_res = sql_query("SELECT COUNT(*) as cnt FROM Airports")
airports_count = airports_count_res.get("result", [{}])[0].get("cnt", 0)

edges_count_res = sql_query("SELECT COUNT(*) as cnt FROM IsInCountry")
edges_count = edges_count_res.get("result", [{}])[0].get("cnt", 0)

# 3. Sample Data Check (Check specific records for accuracy)
# Check FCO (Rome) and JFK (New York)
samples_res = sql_query("SELECT IataCode, City, Country, Latitude, Longitude, Altitude FROM Airports WHERE IataCode IN [\"FCO\", \"JFK\"]")
samples = samples_res.get("result", [])

# 4. Check Edge Connectivity
# Verify FCO connects to Italy
fco_links_res = sql_query("SELECT expand(out(\"IsInCountry\")) FROM Airports WHERE IataCode=\"FCO\"")
fco_links = [r.get("Name") for r in fco_links_res.get("result", [])]

# Construct Result JSON
result = {
    "classes_exist": {
        "Airports": "Airports" in classes,
        "IsInCountry": "IsInCountry" in classes
    },
    "airports_properties": airports_class.get("properties", []),
    "airports_indexes": airports_class.get("indexes", []),
    "counts": {
        "airports": airports_count,
        "edges": edges_count
    },
    "samples": samples,
    "fco_connected_countries": fco_links,
    "timestamp": float(open("/tmp/task_start_time.txt").read().strip())
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Exported result to /tmp/task_result.json")
'

# Set permissions for copy
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="