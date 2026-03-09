#!/bin/bash
set -e

echo "=== Setting up Public Event Registration Task ==="

source /workspace/scripts/task_utils.sh

# Fallback query function
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Ensure LimeSurvey is ready
wait_for_limesurvey() {
    for i in {1..30}; do
        if curl -s http://localhost/index.php/admin >/dev/null; then
            return 0
        fi
        sleep 2
    done
    return 1
}
wait_for_limesurvey

# Create the base survey "Global Tech Summit 2024" using Python API
# This ensures a consistent starting state
echo "Creating base survey..."
python3 << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"

def api(method, params):
    data = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=10).read())
    except Exception as e:
        return {"result": None, "error": str(e)}

# Get session
session = None
for _ in range(5):
    resp = api("get_session_key", ["admin", "Admin123!"])
    s = resp.get("result")
    if s and isinstance(s, str) and "error" not in s.lower():
        session = s
        break
    time.sleep(2)

if not session:
    print("Failed to get session key")
    sys.exit(1)

# Delete if exists
surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if "Global Tech Summit" in s.get("surveyls_title", ""):
            api("delete_survey", [session, s["sid"]])
            print(f"Deleted existing survey {s['sid']}")

# Create new survey
sid = api("add_survey", [session, 0, "Global Tech Summit 2024", "en"])["result"]
print(f"Created survey {sid}")

# Add a basic question group
gid = api("add_group", [session, sid, "Registration Details", ""])["result"]

# Add a basic question (Name)
q_data = {"title": "NAME", "type": "S", "mandatory": "Y", "question": "Please confirm your full name"}
api("add_question", [session, sid, gid, "en", q_data])

api("release_session_key", [session])
PYEOF

# Get the SID of the created survey
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE ls.surveyls_title='Global Tech Summit 2024' LIMIT 1")

if [ -z "$SID" ]; then
    echo "ERROR: Failed to create survey. Exiting."
    exit 1
fi

echo "$SID" > /tmp/task_sid
echo "Survey ID: $SID"

# Initialize participants table (tokens) manually via DB to ensure it exists but is clean
# LimeSurvey's "activate_tokens" API might be needed, or we let the agent do it.
# The task description implies "Enable tokens" is part of the task if they need to add attributes.
# However, usually one initializes tokens first.
# To make it realistic, we will NOT initialize the token table. 
# The agent must click "Survey participants" -> "Initialize participant table".
# BUT, if the token table doesn't exist, they can't add attributes.
# Wait, standard workflow: 
# 1. Initialize tokens.
# 2. Manage attributes.
# So we leave it uninitialized to test if they can find "Participant settings".

# Record start time
date +%s > /tmp/task_start_time

# Setup Firefox
echo "Launching Firefox..."
if pgrep -f firefox > /dev/null; then
    pkill -f firefox
    sleep 2
fi

su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/default.profile 'http://localhost/index.php/admin' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox started."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="