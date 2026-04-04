#!/bin/bash
echo "=== Exporting Country Dashboard Materialization Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python script to inspect database state and validate logic
# We do this INSIDE the container to have direct access to localhost:2480
# The result is saved to a JSON file for the host verifier to read.

cat > /tmp/inspect_dashboard.py << 'PYEOF'
import sys
import json
import urllib.request
import base64

ORIENTDB_URL = "http://localhost:2480"
DB_NAME = "demodb"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def sql_command(command):
    try:
        req = urllib.request.Request(
            f"{ORIENTDB_URL}/command/{DB_NAME}/sql",
            data=json.dumps({"command": command}).encode(),
            headers=HEADERS,
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

def get_schema():
    try:
        req = urllib.request.Request(
            f"{ORIENTDB_URL}/database/{DB_NAME}",
            headers=HEADERS,
            method="GET"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

def main():
    result = {
        "class_exists": False,
        "properties": {},
        "indexes": [],
        "record_count": 0,
        "data_samples": [],
        "ground_truth": {},
        "errors": []
    }

    # 1. Check Schema
    schema = get_schema()
    if "error" in schema:
        result["errors"].append(f"Schema fetch error: {schema['error']}")
    else:
        classes = schema.get("classes", [])
        dashboard_cls = next((c for c in classes if c["name"] == "CountryDashboard"), None)
        
        if dashboard_cls:
            result["class_exists"] = True
            
            # Get properties
            for prop in dashboard_cls.get("properties", []):
                result["properties"][prop["name"]] = prop["type"]
            
            # Get indexes
            for idx in dashboard_cls.get("indexes", []):
                result["indexes"].append({
                    "name": idx["name"],
                    "type": idx["type"],
                    "fields": idx.get("fields", [])
                })

    # 2. Check Data in CountryDashboard
    if result["class_exists"]:
        data_res = sql_command("SELECT FROM CountryDashboard")
        if "result" in data_res:
            records = data_res["result"]
            result["record_count"] = len(records)
            # Store up to 10 records for verification
            result["data_samples"] = records[:10]
        else:
            result["errors"].append("Failed to query CountryDashboard")

    # 3. Compute Ground Truth (Aggregation) for validation
    # We calculate what the values SHOULD be using the raw Hotels/Restaurants tables
    gt_res = sql_command("""
        SELECT 
            Country,
            count(*) as h_count,
            avg(Stars) as h_avg
        FROM Hotels 
        GROUP BY Country
    """)
    
    rest_res = sql_command("""
        SELECT 
            Country, 
            count(*) as r_count 
        FROM Restaurants 
        GROUP BY Country
    """)

    # Process Ground Truth
    gt_map = {}
    
    if "result" in gt_res:
        for row in gt_res["result"]:
            c = row.get("Country")
            if c:
                if c not in gt_map: gt_map[c] = {"h": 0, "r": 0, "avg": 0.0}
                gt_map[c]["h"] = row.get("h_count", 0)
                gt_map[c]["avg"] = row.get("h_avg", 0.0)

    if "result" in rest_res:
        for row in rest_res["result"]:
            c = row.get("Country")
            if c:
                if c not in gt_map: gt_map[c] = {"h": 0, "r": 0, "avg": 0.0}
                gt_map[c]["r"] = row.get("r_count", 0)

    result["ground_truth"] = gt_map

    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
PYEOF

# Run the inspection script
echo "Running inspection script..."
python3 /tmp/inspect_dashboard.py > /tmp/inspection_result.json 2>/dev/null

# Create final task result JSON (combining timestamps + inspection data)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "inspection": $(cat /tmp/inspection_result.json)
}
EOF

# Set permissions for copy_from_env
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="