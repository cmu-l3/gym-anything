#!/bin/bash
set -e
echo "=== Setting up PTO Date Calculation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LimeSurvey is running
wait_for_page_load 5

# Clean up any previous runs: Delete survey if it exists
echo "Checking for existing PTO survey..."
SURVEY_ID=$(get_survey_id "PTO Request Form 2024")

if [ -n "$SURVEY_ID" ]; then
    echo "Found existing survey $SURVEY_ID. Deleting..."
    # We use a python script to invoke the JSON-RPC API or just raw SQL to delete for setup speed
    # SQL is risky for full cleanup, but sufficient for a fresh start in a disposable container
    # However, safest is to drop it via API if possible, or just let the agent create a new one (might duplicate).
    # We'll use the API via Python for cleanliness.
    
    python3 - << PYEOF
import json, urllib.request

BASE = "http://localhost/index.php/admin/remotecontrol"
SID = $SURVEY_ID

def rpc(method, params):
    payload = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=payload, headers={"Content-Type": "application/json"})
    try:
        resp = urllib.request.urlopen(req, timeout=5)
        return json.loads(resp.read())
    except Exception as e:
        print(f"RPC Error: {e}")
        return {}

# Get Session
res = rpc("get_session_key", ["admin", "Admin123!"])
key = res.get("result")
if key:
    print(f"Deleting survey {SID}...")
    rpc("delete_survey", [key, SID])
    rpc("release_session_key", [key])
PYEOF
    
    echo "Survey deleted."
fi

# Record initial state
echo "0" > /tmp/initial_survey_count

# Ensure Firefox is open and focused on Admin login
focus_firefox
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="