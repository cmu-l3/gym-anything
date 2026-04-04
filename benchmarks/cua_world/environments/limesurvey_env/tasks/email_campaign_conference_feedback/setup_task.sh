#!/bin/bash
echo "=== Setting up Email Campaign Task ==="

source /workspace/scripts/task_utils.sh

# Function to execute Python scripts for API interaction
run_python_setup() {
    python3 - << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"

def api(method, params):
    payload = {"method": method, "params": params, "id": 1}
    data = json.dumps(payload).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    try:
        response = urllib.request.urlopen(req, timeout=10)
        return json.loads(response.read())
    except Exception as e:
        return {"error": str(e)}

# Wait for API availability
session_key = None
for i in range(20):
    res = api("get_session_key", ["admin", "Admin123!"])
    if isinstance(res.get("result"), str) and "error" not in str(res.get("result")):
        session_key = res["result"]
        break
    time.sleep(3)

if not session_key:
    print("Failed to get session key")
    sys.exit(1)

# Clean up existing surveys with similar titles
surveys = api("list_surveys", [session_key]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if "2024 SIOP" in s.get("surveyls_title", ""):
            api("delete_survey", [session_key, s["sid"]])
            print(f"Deleted existing survey: {s['surveyls_title']}")

# Create Survey
sid = api("add_survey", [session_key, 0, "2024 SIOP Annual Conference Feedback", "en"])["result"]
print(f"Created survey SID: {sid}")

# Create Groups
gid1 = api("add_group", [session_key, sid, "Session Ratings", ""])["result"]
gid2 = api("add_group", [session_key, sid, "Overall Experience", ""])["result"]

# Add Questions
# Q1: Session Rating (List Radio)
q1_data = {"title": "Q1", "type": "L", "mandatory": "Y", "question": "How would you rate the keynote session?"}
api("add_question", [session_key, sid, gid1, "en", q1_data])

# Q2: Overall Satisfaction (5 point choice)
q2_data = {"title": "Q2", "type": "5", "mandatory": "Y", "question": "Overall satisfaction with the conference."}
api("add_question", [session_key, sid, gid2, "en", q2_data])

# Activate Survey
api("activate_survey", [session_key, sid])

# Initialize Tokens (Attribute fields)
api("activate_tokens", [session_key, sid, [
    {"attribute": "attribute_1", "description": "Job Title"},
    {"attribute": "attribute_2", "description": "Organization"}
]])

# Add Participants
participants = [
    {"email": "r.martinez@stateuniversity.edu", "firstname": "Rebecca", "lastname": "Martinez"},
    {"email": "j.chen@talentinsights.com", "firstname": "James", "lastname": "Chen"},
    {"email": "a.patel@behaviorscience.org", "firstname": "Aisha", "lastname": "Patel"},
    {"email": "m.obrien@globalcorp.com", "firstname": "Michael", "lastname": "O'Brien"},
    {"email": "s.kim@westcoastuniv.edu", "firstname": "Sarah", "lastname": "Kim"},
    {"email": "t.wright@hranalytics.com", "firstname": "Thomas", "lastname": "Wright"}
]
api("add_participants", [session_key, sid, participants, True])

print(f"SURVEY_ID={sid}")
PYEOF
}

# Run setup
echo "Configuring LimeSurvey..."
OUTPUT=$(run_python_setup)
SID=$(echo "$OUTPUT" | grep "SURVEY_ID=" | cut -d'=' -f2)

if [ -z "$SID" ]; then
    echo "ERROR: Failed to create survey"
    exit 1
fi

echo "$SID" > /tmp/task_survey_id
echo "Survey ID: $SID"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox
echo "Launching Firefox..."
focus_firefox
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="