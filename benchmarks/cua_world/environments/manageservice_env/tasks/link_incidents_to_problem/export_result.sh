#!/bin/bash
echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png ga

# Retrieve API Key again for verification query
API_KEY=$(get_sdp_api_key_from_db)

# Run Python script to fetch current associations
cat > /tmp/fetch_results.py << PYEOF
import requests
import json
import os

API_KEY = "$API_KEY"
BASE_URL = "http://localhost:8080/api/v3"
HEADERS = {
    "TECHNICIAN_KEY": API_KEY,
    "Content-Type": "application/x-www-form-urlencoded"
}

result_data = {
    "scenario_loaded": False,
    "problem_id": None,
    "associated_requests": [],
    "target_ids": [],
    "distractor_ids": [],
    "api_success": False
}

# Load scenario IDs created during setup
if os.path.exists("/tmp/scenario_ids.json"):
    with open("/tmp/scenario_ids.json", "r") as f:
        scenario = json.load(f)
        result_data["scenario_loaded"] = True
        result_data["problem_id"] = scenario.get("problem_id")
        result_data["target_ids"] = scenario.get("target_request_ids", [])
        result_data["distractor_ids"] = scenario.get("distractor_request_ids", [])

if result_data["problem_id"]:
    pid = result_data["problem_id"]
    print(f"Checking associations for Problem ID: {pid}")
    
    # Fetch Problem details including associations
    # Note: API endpoint might be /problems/{id}/requests or included in /problems/{id}
    # We will try the direct association endpoint first
    try:
        url = f"{BASE_URL}/problems/{pid}/requests" 
        resp = requests.get(url, headers=HEADERS, verify=False)
        
        if resp.status_code == 200:
            data = resp.json()
            # Parse the requests list
            # Structure usually: {"requests": [{"id": "1", ...}, ...]}
            if "requests" in data:
                reqs = data["requests"]
                result_data["associated_requests"] = [str(r.get("id")) for r in reqs]
                result_data["api_success"] = True
            else:
                print("No 'requests' key in response")
        else:
            print(f"API Failed: {resp.status_code} {resp.text}")
            # Fallback: SQL check if API fails (handled in bash below if this python fails)
            
    except Exception as e:
        print(f"Exception checking API: {e}")
else:
    print("Problem ID missing from scenario file")

# Save result
with open("/tmp/task_result_data.json", "w") as f:
    json.dump(result_data, f)
PYEOF

python3 /tmp/fetch_results.py

# Fallback: If API check failed or returned empty (maybe due to version diff), try SQL
# We check if "api_success" is true in the json.
API_SUCCESS=$(grep -o '"api_success": true' /tmp/task_result_data.json)

if [ -z "$API_SUCCESS" ]; then
    echo "API verification failed or incomplete. Running SQL fallback..."
    
    # Read Problem ID from scenario file
    PID=$(grep -o '"problem_id": [0-9]*' /tmp/scenario_ids.json | head -1 | awk '{print $2}')
    
    if [ -n "$PID" ]; then
        # Query: Find requests linked to this problem
        # Table schema assumption: ProblemToRequest maps problem_id -> request_id (workorder_id)
        # Or WorkOrder table has PARENT_WO_ID
        
        # Try generic association table query
        SQL_QUERY="SELECT request_id FROM problemtorequest WHERE problem_id = $PID"
        ASSOCIATED_IDS=$(sdp_db_exec "$SQL_QUERY")
        
        # Format as JSON array string: ["1", "2"]
        JSON_ARRAY="["
        for id in $ASSOCIATED_IDS; do
            JSON_ARRAY="$JSON_ARRAY\"$id\", "
        done
        JSON_ARRAY="${JSON_ARRAY%, }]"
        
        # Update the JSON file using python purely for JSON manipulation
        python3 -c "
import json
try:
    with open('/tmp/task_result_data.json', 'r') as f:
        d = json.load(f)
    d['associated_requests'] = $JSON_ARRAY
    d['sql_fallback_used'] = True
    with open('/tmp/task_result_data.json', 'w') as f:
        json.dump(d, f)
except Exception as e:
    print(e)
"
    fi
fi

# Prepare final JSON for verifier
cp /tmp/task_result_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json