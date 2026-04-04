#!/bin/bash
set -e
echo "=== Setting up Annual Survey Rollover Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be ready
echo "Waiting for LimeSurvey..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin >/dev/null; then
        break
    fi
    sleep 2
done

# Ensure API is enabled in DB (just in case)
limesurvey_query "INSERT INTO lime_settings_global (stg_name, stg_value) VALUES ('RPCInterface', 'json') ON DUPLICATE KEY UPDATE stg_value='json';" 2>/dev/null

# Create the initial "Employee Pulse 2024" survey using Python + JSON-RPC
# This ensures a clean, valid starting state
python3 - << 'EOF'
import json
import urllib.request
import sys
import time

URL = "http://localhost/index.php/admin/remotecontrol"
USER = "admin"
PASS = "Admin123!"

def rpc(method, *params):
    payload = {
        "method": method,
        "params": params,
        "id": 1
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        URL, 
        data=data, 
        headers={"Content-Type": "application/json"}
    )
    try:
        response = urllib.request.urlopen(req)
        return json.loads(response.read()).get("result")
    except Exception as e:
        return None

# Get Session Key
key = None
for i in range(10):
    key = rpc("get_session_key", USER, PASS)
    if key and isinstance(key, str) and "error" not in key.lower():
        break
    time.sleep(1)

if not key:
    print("Failed to get session key")
    sys.exit(1)

# Clean up any existing surveys with the task titles
surveys = rpc("list_surveys", key)
if surveys and isinstance(surveys, list):
    for s in surveys:
        title = s.get("surveyls_title", "")
        if title in ["Employee Pulse 2024", "Employee Pulse 2025"]:
            rpc("delete_survey", key, s.get("sid"))
            print(f"Deleted existing survey: {title}")

# Create Base Survey: Employee Pulse 2024
sid = rpc("add_survey", key, 0, "Employee Pulse 2024", "en")
print(f"Created Base Survey SID: {sid}")

# Add Group 1: Core Engagement (should be kept)
gid1 = rpc("add_group", key, sid, "Core Engagement")
rpc("add_question", key, sid, gid1, "CORE1", "I am satisfied with my role.", "I am satisfied with my role.", "L", "Y", "N")

# Add Group 2: 2024 Initiatives (should be deleted)
gid2 = rpc("add_group", key, sid, "2024 Initiatives")
rpc("add_question", key, sid, gid2, "INIT24_1", "How many days do you work remotely?", "Remote work frequency", "L", "Y", "N")

# Activate it (optional, but realistic)
rpc("activate_survey", key, sid)

rpc("release_session_key", key)
EOF

# Record ID of the source survey
SOURCE_SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title='Employee Pulse 2024' LIMIT 1")
echo "$SOURCE_SID" > /tmp/source_survey_sid.txt
echo "Source Survey ID: $SOURCE_SID"

# Launch Firefox
if ! pgrep -f "firefox" > /dev/null; then
    echo "Launching Firefox..."
    su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/default.profile 'http://localhost/index.php/admin' &"
else
    # Navigate to admin home
    su - ga -c "DISPLAY=:1 firefox -new-tab 'http://localhost/index.php/admin' &"
fi

# Wait for window
wait_for_window "Firefox" 20

# Maximize and focus
focus_firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="