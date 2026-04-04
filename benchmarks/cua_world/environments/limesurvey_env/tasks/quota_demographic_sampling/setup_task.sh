#!/bin/bash
set -e
echo "=== Setting up Quota Demographic Sampling Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LimeSurvey is ready
echo "Waiting for LimeSurvey API..."
wait_for_limesurvey_api || exit 1

# Create the survey structure using Python and RemoteControl API
# This ensures a clean, consistent starting state
python3 << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"

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
        return {"error": str(e)}

# 1. Get Session Key
session_key = None
for i in range(5):
    res = api("get_session_key", ["admin", "Admin123!"])
    if isinstance(res.get("result"), str) and "error" not in str(res.get("result", "")).lower():
        session_key = res["result"]
        break
    time.sleep(2)

if not session_key:
    print("Failed to get session key")
    sys.exit(1)

# 2. Cleanup existing survey if it exists
surveys = api("list_surveys", [session_key]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if s.get("surveyls_title") == "Consumer Electronics Satisfaction Study Q4 2024":
            api("delete_survey", [session_key, s["sid"]])
            print(f"Deleted existing survey {s['sid']}")

# 3. Create Survey
sid = api("add_survey", [session_key, 0, "Consumer Electronics Satisfaction Study Q4 2024", "en"])["result"]
print(f"Created survey SID: {sid}")

# Write SID to file for other scripts
with open("/tmp/task_survey_id.txt", "w") as f:
    f.write(str(sid))

# 4. Create Groups
gid_demog = api("add_group", [session_key, sid, "Respondent Demographics", "Basic info"])["result"]
gid_prod = api("add_group", [session_key, sid, "Product Experience", "Feedback"])["result"]

# 5. Create Gender Question (The target for quotas)
q_gender_data = {
    "title": "GENDER",
    "type": "L", # List (Radio)
    "mandatory": "Y",
    "question": "What is your gender identity?"
}
qid_gender = api("add_question", [session_key, sid, gid_demog, "en", q_gender_data])["result"]

# Add Answers for Gender
api("add_answer", [session_key, sid, qid_gender, "M", "en", "Male"])
api("add_answer", [session_key, sid, qid_gender, "F", "en", "Female"])
api("add_answer", [session_key, sid, qid_gender, "NB", "en", "Non-binary"])

# Write Gender QID to file
with open("/tmp/task_gender_qid.txt", "w") as f:
    f.write(str(qid_gender))

# 6. Create Age Question (Distractor)
q_age_data = {
    "title": "AGE",
    "type": "L",
    "mandatory": "Y",
    "question": "Which age group do you belong to?"
}
qid_age = api("add_question", [session_key, sid, gid_demog, "en", q_age_data])["result"]
api("add_answer", [session_key, sid, qid_age, "A1", "en", "18-24"])
api("add_answer", [session_key, sid, qid_age, "A2", "en", "25-34"])
api("add_answer", [session_key, sid, qid_age, "A3", "en", "35+"])

# 7. Create Satisfaction Question
q_sat_data = {
    "title": "SAT",
    "type": "5", # 5 point choice
    "mandatory": "N",
    "question": "Overall, how satisfied are you with our products?"
}
api("add_question", [session_key, sid, gid_prod, "en", q_sat_data])

api("release_session_key", [session_key])
print("Survey setup complete.")
PYEOF

# Verify setup files exist
if [ ! -f /tmp/task_survey_id.txt ]; then
    echo "Error: Survey ID not saved"
    exit 1
fi

SURVEY_ID=$(cat /tmp/task_survey_id.txt)
echo "Survey ID: $SURVEY_ID"

# Record initial quota count (should be 0)
INITIAL_QUOTA_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_quota WHERE sid=$SURVEY_ID")
echo "$INITIAL_QUOTA_COUNT" > /tmp/initial_quota_count.txt

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox and navigate to survey summary
echo "Launching Firefox..."
focus_firefox
# Navigate directly to the survey overview
DISPLAY=:1 xdotool type "http://localhost/index.php/admin/survey/sa/view/surveyid/$SURVEY_ID"
DISPLAY=:1 xdotool key Return
sleep 5

# Ensure window maximized
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="