#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting document_problem_rca result ==="

# Final Screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROBLEM_ID=$(cat /tmp/problem_id.txt 2>/dev/null)
API_KEY=$(get_sdp_api_key_from_db)

# We will export data by querying the API (preferred) or DB
# DB is backup because schema 'problemanalysis' vs 'solution' can vary
# But API gives structured JSON which is easier to parse

echo "Fetching final problem state..."

cat > /tmp/fetch_problem_result.py << PYEOF
import requests
import json
import sys

problem_id = "$PROBLEM_ID"
api_key = "$API_KEY"
base_url = "https://localhost:8080/api/v3/problems"

result = {
    "problem_found": False,
    "analysis": {},
    "solution": {},
    "api_error": None
}

if not problem_id or not api_key:
    result["api_error"] = "Missing Problem ID or API Key"
    print(json.dumps(result))
    sys.exit(0)

headers = {"TECHNICIAN_KEY": api_key}

try:
    # 1. Fetch Main Problem Details & Analysis
    # Analysis is often nested or a separate endpoint depending on SDP version
    # Try main endpoint first
    url = f"{base_url}/{problem_id}"
    resp = requests.get(url, headers=headers, verify=False, timeout=10)
    
    if resp.status_code == 200:
        data = resp.json()
        if data.get("response_status", {}).get("status") == "success":
            result["problem_found"] = True
            prob_data = data.get("problem", {})
            
            # Extract fields that might contain RCA/Symptoms
            # Note: API field names map to UI labels
            result["analysis"]["root_cause"] = prob_data.get("root_cause", "")
            result["analysis"]["symptoms"] = prob_data.get("symptoms", "")
            result["analysis"]["impact_details"] = prob_data.get("impact_details", "")
    
    # 2. Fetch Solution / Workaround
    # Usually /problems/{id}/solutions or similar
    url_sol = f"{base_url}/{problem_id}/solutions"
    resp_sol = requests.get(url_sol, headers=headers, verify=False, timeout=10)
    
    if resp_sol.status_code == 200:
        sol_data = resp_sol.json()
        if sol_data.get("response_status", {}).get("status") == "success":
            solutions = sol_data.get("solutions", [])
            if solutions:
                # Get the most recent solution/workaround
                result["solution"] = solutions[0]

except Exception as e:
    result["api_error"] = str(e)

# 3. DB FALLBACK
# If API failed to show RCA (sometimes fields are custom), assume DB check
# We print a special marker to let bash script know to run DB query
print(json.dumps(result))
PYEOF

# Run Python fetcher
python3 /tmp/fetch_problem_result.py > /tmp/api_result.json

# If API result is empty/error, or missing RCA, try direct DB dump as backup
# This helps if API permissions are restricted or field names mismatch
echo "Performing DB backup query..."

# Dump relevant table columns for the problem
DB_DUMP_FILE="/tmp/db_dump.json"

# Check 'problemanalysis' table (common in SDP)
# Columns: problem_id, root_cause, symptoms, impact
RCA_SQL="SELECT root_cause, symptoms FROM problemanalysis WHERE problem_id=${PROBLEM_ID:-0}"
RCA_DATA=$(sdp_db_exec "$RCA_SQL" "servicedesk")

# Check 'problemsolution' or 'solution' table
# Columns: problem_id, description, workaround
SOL_SQL="SELECT description, workaround FROM problemsolution WHERE problem_id=${PROBLEM_ID:-0}"
SOL_DATA=$(sdp_db_exec "$SOL_SQL" "servicedesk")

# Create final combined result
cat > /tmp/create_final_json.py << PYEOF
import json
import time

try:
    with open("/tmp/api_result.json", "r") as f:
        api_data = json.load(f)
except:
    api_data = {}

db_rca = """$RCA_DATA"""
db_sol = """$SOL_DATA"""

final_result = {
    "timestamp": time.time(),
    "problem_id": "$PROBLEM_ID",
    "api_data": api_data,
    "db_data": {
        "rca_raw": db_rca,
        "sol_raw": db_sol
    },
    "screenshot_path": "/tmp/task_final.png"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(final_result, f, indent=2)
PYEOF

python3 /tmp/create_final_json.py

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="