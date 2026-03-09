#!/bin/bash
set -e
echo "=== Setting up Dynamic Email Routing Task ==="

source /workspace/scripts/task_utils.sh

# Define helper for DB queries if not present
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the survey and questions using Python API
# This ensures a clean state with the specific structure needed for the task
echo "Creating IT Incident Report survey..."
python3 << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"
ADMIN_USER = "admin"
ADMIN_PASS = "Admin123!"

def api(method, params):
    payload = {
        "method": method,
        "params": params,
        "id": 1
    }
    req = urllib.request.Request(
        BASE, 
        data=json.dumps(payload).encode(), 
        headers={"Content-Type": "application/json"}
    )
    try:
        response = urllib.request.urlopen(req, timeout=10)
        return json.loads(response.read())
    except Exception as e:
        return {"result": None, "error": str(e)}

# Get Session Key
session_key = None
for i in range(10):
    res = api("get_session_key", [ADMIN_USER, ADMIN_PASS])
    if isinstance(res.get("result"), str) and len(res["result"]) > 10:
        session_key = res["result"]
        break
    time.sleep(2)

if not session_key:
    print("Failed to get session key")
    sys.exit(1)

# Clean up existing survey if it exists
surveys = api("list_surveys", [session_key]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if s.get("surveyls_title") == "IT Incident Report Form 2025":
            api("delete_survey", [session_key, s["sid"]])
            print(f"Deleted existing survey {s['sid']}")

# Create Survey
survey_id = api("add_survey", [session_key, 0, "IT Incident Report Form 2025", "en", "G"]).get("result")
print(f"Created survey: {survey_id}")

# Add Group
group_id = api("add_group", [session_key, survey_id, "Incident Details", "Primary incident information"]).get("result")
print(f"Created group: {group_id}")

# Add Question (List Radio)
# Code: Severity
question_data = {
    "title": "Severity",
    "type": "L",  # List (Radio)
    "mandatory": "Y",
    "question_order": 0
}
question_l10n = {
    "question": "What is the severity of this incident?"
}
qid = api("add_question", [session_key, survey_id, group_id, "en", question_data, question_l10n]).get("result")
print(f"Created question 'Severity': {qid}")

# Add Answer Options
# L1: Critical
# L2: Standard
api("add_answer", [session_key, survey_id, qid, "L1", "en", "Critical (System Down)"])
api("add_answer", [session_key, survey_id, qid, "L2", "en", "Standard (Performance/Bug)"])

# Release session
api("release_session_key", [session_key])
print("Setup complete")
PYEOF

# Ensure Firefox is running and focused
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        DISPLAY=:1 wmctrl -a "Firefox"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="