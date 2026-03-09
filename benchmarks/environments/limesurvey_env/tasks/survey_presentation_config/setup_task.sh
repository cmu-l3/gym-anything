#!/bin/bash
set -e
echo "=== Setting up Survey Presentation Config Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the survey using Python/API to ensure correct structure
# We use Python because creating groups/questions via raw SQL is complex and error-prone
echo "Creating initial survey structure..."
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
    if resp.get("result") and "error" not in str(resp.get("result")):
        session = resp["result"]
        break
    time.sleep(2)

if not session:
    print("Failed to get session key")
    sys.exit(1)

# Delete existing survey if present
surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if "TechSummit 2024" in s.get("surveyls_title", ""):
            api("delete_survey", [session, s["sid"]])
            print(f"Deleted existing survey {s['sid']}")

# Create Survey
# Params: session, survey_id (0=new), title, language, format (S=Question by Question default)
sid = api("add_survey", [session, 0, "TechSummit 2024 Attendee Feedback", "en", "S"])["result"]
print(f"Created survey SID: {sid}")

# Create Groups
g1 = api("add_group", [session, sid, "Overall Experience", "Reaction"])["result"]
g2 = api("add_group", [session, sid, "Session Quality", "Learning"])["result"]
g3 = api("add_group", [session, sid, "Logistics", "Environment"])["result"]

# Add Questions (Sample)
api("add_question", [session, sid, g1, "en", {"title": "Q1", "type": "5", "question": "Rate your overall experience"}, [], [], []])
api("add_question", [session, sid, g2, "en", {"title": "Q4", "type": "5", "question": "Rate the keynote quality"}, [], [], []])
api("add_question", [session, sid, g3, "en", {"title": "Q7", "type": "T", "question": "Suggestions for improvement"}, [], [], []])

api("release_session_key", [session])
print(sid)
PYEOF

# Get the SID created above (it's the last line of output)
SID=$(python3 -c "import sys; lines=[l.strip() for l in sys.stdin if l.strip().isdigit()]; print(lines[-1] if lines else '')" < <(python3 - << 'PYEOF'
import json, urllib.request
# Re-run a quick list to find the ID if the previous script output was messy
BASE = "http://localhost/index.php/admin/remotecontrol"
req = urllib.request.Request(BASE, data=json.dumps({"method":"get_session_key","params":["admin","Admin123!"],"id":1}).encode(), headers={"Content-Type":"application/json"})
s = json.loads(urllib.request.urlopen(req).read()).get("result")
req2 = urllib.request.Request(BASE, data=json.dumps({"method":"list_surveys","params":[s],"id":1}).encode(), headers={"Content-Type":"application/json"})
surveys = json.loads(urllib.request.urlopen(req2).read()).get("result", [])
for surv in surveys:
    if "TechSummit" in surv.get("surveyls_title", ""):
        print(surv.get("sid"))
PYEOF
))

if [ -z "$SID" ]; then
    echo "ERROR: Could not verify survey creation"
    exit 1
fi

echo "Survey ID is $SID"
echo "$SID" > /tmp/task_survey_id.txt

# Reset settings to KNOWN DEFAULTS (Bad State) directly via DB
# This ensures the agent must actually change them
limesurvey_query "UPDATE lime_surveys SET format='S', showprogress='N', printanswers='N', allowprev='N', autoredirect='N' WHERE sid=$SID"
limesurvey_query "UPDATE lime_surveys_languagesettings SET surveyls_welcometext='', surveyls_endtext='', surveyls_url='' WHERE surveyls_survey_id=$SID"

# Verify initial state
echo "Initial state recorded:"
limesurvey_query "SELECT sid, format, showprogress, printanswers, allowprev, autoredirect FROM lime_surveys WHERE sid=$SID" > /tmp/initial_db_state.txt
cat /tmp/initial_db_state.txt

# Start Firefox and navigate to Admin login
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox running"
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="