#!/bin/bash
echo "=== Setting up CPDB Panel Management Task ==="

source /workspace/scripts/task_utils.sh

# Define query helper if not present
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Wait for LimeSurvey to be ready
echo "Waiting for LimeSurvey..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin >/dev/null; then
        echo "LimeSurvey is ready."
        break
    fi
    sleep 2
done

# Clear existing CPDB data to ensure clean state
# This removes participants, attributes, and links to ensure the agent does the work
echo "Cleaning Central Participant Database..."
limesurvey_query "DELETE FROM lime_participant_attribute"
limesurvey_query "DELETE FROM lime_participant_attribute_names"
limesurvey_query "DELETE FROM lime_participants"
limesurvey_query "DELETE FROM lime_survey_links"

# Create the target survey "Q1 2024 Brand Perception Tracker" using Python API
# The survey needs to be active and have a token table initialized
echo "Creating target survey..."
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

# Get Session
session = None
for i in range(10):
    resp = api("get_session_key", ["admin", "Admin123!"])
    s = resp.get("result")
    if s and isinstance(s, str) and "error" not in s.lower():
        session = s
        break
    time.sleep(2)

if not session:
    print("Failed to get session key")
    sys.exit(1)

# Check if survey exists and delete it
surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if "Brand Perception Tracker" in s.get("surveyls_title", ""):
            api("delete_survey", [session, s["sid"]])

# Create Survey
sid = api("add_survey", [session, 0, "Q1 2024 Brand Perception Tracker", "en", "G"])["result"]
print(f"Created Survey SID: {sid}")

# Add Group
gid = api("add_group", [session, sid, "Brand Awareness", ""])["result"]

# Add Question
q_data = {"title": "Q1", "type": "L", "mandatory": "N", "question": "How familiar are you with our brand?"}
api("add_question", [session, sid, gid, "en", q_data, [], [], []])

# Activate Survey (this automatically initializes the token table)
api("activate_survey", [session, sid])

# Initialize token table explicitly if activation didn't (though activation usually does)
# But strictly speaking, CPDB sharing requires the survey to be initialized.
# API activate_survey does this.

api("release_session_key", [session])
PYEOF

# Get the SID of the new survey for verification reference
SURVEY_ID=$(limesurvey_query "SELECT sid FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Brand Perception Tracker%' LIMIT 1")
echo "Target Survey ID: $SURVEY_ID"
echo "$SURVEY_ID" > /tmp/target_survey_id.txt

# Record initial counts for anti-gaming
echo "0" > /tmp/initial_cpdb_count.txt
date +%s > /tmp/task_start_time.txt

# Start Firefox
echo "Starting Firefox..."
focus_firefox
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="