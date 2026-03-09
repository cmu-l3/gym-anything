#!/bin/bash
echo "=== Exporting demographic_time_tree result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We need to extract the database state to a JSON file for the verifier.
# We'll use a Python script interacting with the OrientDB REST API to do this robustly.

cat > /tmp/extract_db_state.py << 'EOF'
import sys
import json
import base64
import urllib.request
import urllib.error
from datetime import datetime

DB_NAME = "demodb"
BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def sql_query(command):
    try:
        req = urllib.request.Request(
            f"{BASE_URL}/command/{DB_NAME}/sql",
            data=json.dumps({"command": command}).encode(),
            headers=HEADERS,
            method="POST"
        )
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        # If class doesn't exist, SQL throws 500 or 400. We capture this.
        return {"error": str(e), "result": []}
    except Exception as e:
        return {"error": str(e), "result": []}

def get_schema():
    try:
        req = urllib.request.Request(f"{BASE_URL}/database/{DB_NAME}", headers=HEADERS)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
            return [c['name'] for c in data.get('classes', [])]
    except:
        return []

def main():
    result = {
        "timestamp": datetime.now().isoformat(),
        "schema_classes": get_schema(),
        "errors": []
    }

    # 1. Check Year Uniqueness
    # Query: Get counts of Years by Value
    year_dist = sql_query("SELECT Value, count(*) as c FROM Year GROUP BY Value")
    result['year_distribution'] = year_dist.get('result', [])

    # 2. Check Month Uniqueness (per Year)
    # This is tricky in simple SQL. We'll check total counts.
    # We want to see if multiple months with same value attach to same year.
    # Query: Select Month Value and Parent Year Value
    month_data = sql_query("SELECT Value, in('HasMonth').Value as YearVal FROM Month")
    result['month_data'] = month_data.get('result', [])
    
    # 3. Check Profile Connections (Data Accuracy)
    # We get a sample of profiles to verify their Birthday matches the connected Month/Year
    # Limit to 50 to keep JSON size manageable but statistically significant
    profile_sample = sql_query("SELECT Birthday, out('BornIn').Value as M, out('BornIn').in('HasMonth').Value as Y FROM Profiles LIMIT 50")
    result['profile_samples'] = profile_sample.get('result', [])

    # 4. Global Counts
    counts = {}
    for cls in ["Year", "Month", "Profiles", "HasMonth", "BornIn"]:
        res = sql_query(f"SELECT count(*) as c FROM {cls}")
        if 'result' in res and len(res['result']) > 0:
            counts[cls] = res['result'][0].get('c', 0)
        else:
            counts[cls] = 0
    result['counts'] = counts

    # Write to file
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == "__main__":
    main()
EOF

# Run the python script
python3 /tmp/extract_db_state.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result extracted to /tmp/task_result.json"
echo "=== Export complete ==="