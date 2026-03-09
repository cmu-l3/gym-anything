#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: document_problem_rca ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure ServiceDesk Plus is running
# This utility waits for the background install if needed and starts the service
ensure_sdp_running

# 2. Get API Key for setup automation
echo "Retrieving API Key..."
API_KEY=$(get_sdp_api_key_from_db)

# If key not in DB, generate it via web interaction simulation (provided in task_utils)
if [ -z "$API_KEY" ]; then
    echo "API Key not found in DB. generating via web..."
    write_python_login_script
    generate_api_key_via_web
    API_KEY=$(get_sdp_api_key_from_db)
fi

if [ -z "$API_KEY" ]; then
    echo "CRITICAL ERROR: Could not obtain API key. Setup failed."
    # We will try to proceed, but the agent might have to create the problem manually if we fail here.
    # For now, we exit to signal setup failure.
    exit 1
fi

echo "API Key obtained: ${API_KEY:0:5}..."

# 3. Create the seed Problem record
echo "Creating seed problem record..."
cat > /tmp/create_seed_problem.py << PYEOF
import requests
import json
import sys
import time

url = "https://localhost:8080/api/v3/problems"
headers = {
    "TECHNICIAN_KEY": "$API_KEY",
    "Content-Type": "application/x-www-form-urlencoded"
}

# Define the problem payload
# Note: SDP API v3 format
data = {
    "problem": {
        "title": "Recurring freeze on HR Payroll System",
        "description": "The HR payroll application becomes unresponsive every Friday afternoon. Restarting the server temporarily fixes it. Logs indicate high database contention.",
        "urgency": {"name": "High"},
        "impact": {"name": "High"},
        "priority": {"name": "High"},
        "source": {"name": "Web"},
        "reported_by": {"email_id": "administrator@servicedesk.com"}
    }
}

payload = {"input_data": json.dumps(data)}

# Retry loop for API availability
max_retries = 5
for i in range(max_retries):
    try:
        print(f"Attempt {i+1} to create problem...")
        response = requests.post(url, headers=headers, data=payload, verify=False, timeout=10)
        
        if response.status_code in [200, 201]:
            resp_json = response.json()
            if resp_json.get("response_status", {}).get("status") == "success":
                problem_id = resp_json.get("problem", {}).get("id")
                print(f"SUCCESS: Created Problem ID {problem_id}")
                with open("/tmp/problem_id.txt", "w") as f:
                    f.write(str(problem_id))
                sys.exit(0)
            else:
                print(f"API Error: {resp_json}")
        else:
            print(f"HTTP Error: {response.status_code} - {response.text}")
            
    except Exception as e:
        print(f"Connection Error: {e}")
    
    time.sleep(5)

print("FAILED to create problem after retries")
sys.exit(1)
PYEOF

python3 /tmp/create_seed_problem.py

# 4. Launch Firefox to the Problems list
echo "Launching Firefox..."
if [ -f "/tmp/problem_id.txt" ]; then
    PID=$(cat /tmp/problem_id.txt)
    # Go directly to the problem or the list
    TARGET_URL="https://localhost:8080/ManageEngine/sso/Problem.do?problemID=${PID}"
else
    # Fallback
    TARGET_URL="https://localhost:8080/ManageEngine/Login.do"
fi

ensure_firefox_on_sdp "$TARGET_URL"

# 5. Capture initial state
sleep 5
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="