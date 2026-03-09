#!/bin/bash
set -e
echo "=== Setting up Clinical Safety Protocol Config Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey readiness
wait_for_limesurvey 120

# Create the specific survey scenario via Python/API
# We need a survey with a specific question code 'safety_check'
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
for i in range(10):
    try:
        resp = api("get_session_key", ["admin", "Admin123!"])
        if isinstance(resp.get("result"), str) and "error" not in str(resp.get("result")).lower():
            session = resp["result"]
            break
    except:
        pass
    time.sleep(2)

if not session:
    print("Failed to get session key")
    sys.exit(1)

# Clean up existing survey if it exists
surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if "Depression Screening - Fall 2024" in s.get("surveyls_title", ""):
            api("delete_survey", [session, s["sid"]])
            print(f"Deleted existing survey {s['sid']}")

# Create Survey
sid = api("add_survey", [session, 0, "Depression Screening - Fall 2024", "en"])["result"]
print(f"Created survey {sid}")

# Create Group
gid = api("add_group", [session, sid, "Screening Items"])["result"]
print(f"Created group {gid}")

# Create Trigger Question (safety_check)
# Type L (List Radio)
q_data = {
    "title": "safety_check",
    "type": "L",
    "mandatory": "Y",
    "question": "Have you had thoughts of hurting yourself?",
    "question_order": 0
}
qid = api("add_question", [session, sid, gid, "en", q_data])["result"]
print(f"Created question {qid}")

# Add answers Y and N
# Note: add_question usually doesn't add answer options for List types automatically in API v2, 
# but let's try assuming standard API behavior or use DB fallback if needed.
# Using DB for answers is safer/faster in setup script context if API is finicky about subquestions.
PYEOF

# Get the Survey ID we just created to add answers via SQL (more reliable for answers)
SID=$(limesurvey_query "SELECT sid FROM lime_surveys_languagesettings WHERE surveyls_title='Depression Screening - Fall 2024' LIMIT 1")
QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='safety_check'")

if [ -n "$QID" ]; then
    # Insert answer options
    limesurvey_query "INSERT INTO lime_answers (qid, code, answer, sortorder, assessment_value, scale_id) VALUES ($QID, 'N', 'No', 1, 0, 0), ($QID, 'Y', 'Yes', 2, 1, 0);"
    # Insert localization
    # (Note: lime_answers structure varies by version, usually answer is in lime_answers or lime_answer_l10ns)
    # Checking version: LimeSurvey 6 uses l10ns table.
    limesurvey_query "INSERT INTO lime_answer_l10ns (aid, answer, language) SELECT aid, answer, 'en' FROM lime_answers WHERE qid=$QID;"
fi

echo "$SID" > /tmp/task_sid.txt

# Ensure Firefox is open and focused
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    wait_for_window "Firefox" 20
fi

focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="