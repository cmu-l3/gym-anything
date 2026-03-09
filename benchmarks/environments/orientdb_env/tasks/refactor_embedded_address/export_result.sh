#!/bin/bash
echo "=== Exporting refactor_embedded_address results ==="

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_final.png

# We need to inspect the database schema and data to verify the refactoring.
# We will use a Python script to verify the state internally and dump a JSON result.

cat > /tmp/inspect_result.py << 'EOF'
import sys
import json
import urllib.request
import base64

ORIENTDB_URL = "http://localhost:2480"
DB_NAME = "demodb"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

def get_database_schema():
    req = urllib.request.Request(f"{ORIENTDB_URL}/database/{DB_NAME}", headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"error": str(e)}

def sql_query(command):
    req = urllib.request.Request(
        f"{ORIENTDB_URL}/command/{DB_NAME}/sql",
        data=json.dumps({"command": command}).encode(),
        headers=HEADERS,
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"error": str(e)}

result = {
    "location_class_exists": False,
    "hotels_properties": [],
    "location_properties": [],
    "data_sample": {},
    "errors": []
}

try:
    # 1. Check Schema
    schema = get_database_schema()
    classes = schema.get("classes", [])
    
    hotels_class = next((c for c in classes if c["name"] == "Hotels"), None)
    location_class = next((c for c in classes if c["name"] == "Location"), None)
    
    if hotels_class:
        result["hotels_properties"] = [p["name"] for p in hotels_class.get("properties", [])]
        # Get details of 'Address' property if it exists
        addr_prop = next((p for p in hotels_class.get("properties", []) if p["name"] == "Address"), None)
        if addr_prop:
            result["hotels_address_type"] = addr_prop.get("type")
            result["hotels_address_linked_class"] = addr_prop.get("linkedClass")
            
    if location_class:
        result["location_class_exists"] = True
        result["location_properties"] = [p["name"] for p in location_class.get("properties", [])]
        # Check if it extends V or E (it shouldn't)
        result["location_superclasses"] = location_class.get("superClasses", [])

    # 2. Check Data (Hotel Artemide)
    # We verify if Address is populated and if old fields are null/gone
    query_res = sql_query("SELECT Name, Address, Street, City, Country FROM Hotels WHERE Name='Hotel Artemide'")
    records = query_res.get("result", [])
    if records:
        rec = records[0]
        result["data_sample"] = {
            "Name": rec.get("Name"),
            "Address": rec.get("Address"), # This will be a dict if embedded
            "Street": rec.get("Street"),
            "City": rec.get("City"),
            "Country": rec.get("Country")
        }

except Exception as e:
    result["errors"].append(str(e))

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

# Execute the inspection script
python3 /tmp/inspect_result.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Inspection complete. Result:"
cat /tmp/task_result.json
echo "=== Export complete ==="