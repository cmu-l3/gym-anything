#!/bin/bash
echo "=== Exporting Viral Marketing Results ==="

# Source OrientDB utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Python script to fetch database state safely
cat > /tmp/fetch_results.py << 'EOF'
import sys
import json
import base64
import urllib.request

BASE_URL = "http://localhost:2480"
AUTH = "Basic " + base64.b64encode(b"root:GymAnything123!").decode("utf-8")
HEADERS = {"Authorization": AUTH, "Content-Type": "application/json"}

def get_schema():
    try:
        req = urllib.request.Request(f"{BASE_URL}/database/demodb", headers=HEADERS)
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

def sql_query(command):
    try:
        req = urllib.request.Request(f"{BASE_URL}/command/demodb/sql", 
                                     data=json.dumps({"command": command}).encode(), 
                                     headers=HEADERS, method="POST")
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
            return data.get("result", [])
    except Exception as e:
        return []

results = {
    "timestamp": int(time.time()) if 'time' in globals() else 0,
    "schema": {},
    "profiles": {}
}

import time
results["timestamp"] = int(time.time())

# 1. Fetch Schema to check for new properties
db_info = get_schema()
if "classes" in db_info:
    for cls in db_info["classes"]:
        if cls["name"] == "Profiles":
            props = {p["name"]: p["type"] for p in cls.get("properties", [])}
            results["schema"] = props

# 2. Fetch Test Profiles
test_emails = ["liam.hub@test.com", "damon.pop@test.com", "graham.solo@test.com"]
for email in test_emails:
    data = sql_query(f"SELECT Email, NetworkValue, IsViralHub FROM Profiles WHERE Email='{email}'")
    if data:
        results["profiles"][email] = data[0]

# Write to stdout
print(json.dumps(results, indent=2))
EOF

# Execute fetch script and save to /tmp/task_result.json
python3 /tmp/fetch_results.py > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="