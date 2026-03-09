#!/bin/bash
echo "=== Setting up Public Statistics Transparency Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LimeSurvey API is ready
echo "Waiting for LimeSurvey API..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin/remotecontrol >/dev/null; then
        break
    fi
    sleep 2
done

# Create the survey structure using Python and JSON-RPC
python3 << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"
USER = "admin"
PASS = "Admin123!"

def rpc(method, params, req_id=1):
    data = json.dumps({"method": method, "params": params, "id": req_id}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    try:
        resp = urllib.request.urlopen(req, timeout=10)
        return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

# 1. Get Session Key
print("Getting session key...")
session_key = None
for _ in range(5):
    res = rpc("get_session_key", [USER, PASS])
    if isinstance(res.get("result"), str):
        session_key = res["result"]
        break
    time.sleep(2)

if not session_key:
    print("Failed to get session key")
    sys.exit(1)

# 2. Cleanup existing survey if present
print("Cleaning up old surveys...")
surveys = rpc("list_surveys", [session_key], 2).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if s.get("surveyls_title") == "Participatory Budgeting 2026":
            rpc("delete_survey", [session_key, s["sid"]])

# 3. Create Survey
print("Creating survey...")
sid = rpc("add_survey", [session_key, 0, "Participatory Budgeting 2026", "en", "G"]).get("result")
print(f"Created Survey ID: {sid}")

# 4. Create Groups
gid1 = rpc("add_group", [session_key, sid, "Project Vote", "Main voting section"]).get("result")
gid2 = rpc("add_group", [session_key, sid, "Resident Demographics", "Demographic info"]).get("result")

# 5. Create Questions
# Q1: Project Preference (List Radio)
q1_data = {"title": "PROJ", "type": "L", "mandatory": "Y", "question": "Which project is your top priority?"}
qid1 = rpc("add_question", [session_key, sid, gid1, "en", q1_data, [], [], []]).get("result")

# Add answers for Q1
rpc("add_answer", [session_key, sid, qid1, "A1", "en", "Downtown Bike Lane Network"])
rpc("add_answer", [session_key, sid, qid1, "A2", "en", "Riverside Park Amphitheater"])
rpc("add_answer", [session_key, sid, qid1, "A3", "en", "Community Solar Microgrid"])

# Q2: Priority Score (Numerical)
q2_data = {"title": "SCORE", "type": "N", "mandatory": "N", "question": "Assign a priority score (1-10) for your choice."}
qid2 = rpc("add_question", [session_key, sid, gid1, "en", q2_data, [], [], []]).get("result")

# Q3: Zip Code (Short Text)
q3_data = {"title": "ZIP", "type": "S", "mandatory": "Y", "question": "What is your Zip Code?"}
qid3 = rpc("add_question", [session_key, sid, gid2, "en", q3_data, [], [], []]).get("result")

# Q4: Household Income (List Radio)
q4_data = {"title": "INC", "type": "L", "mandatory": "N", "question": "What is your annual household income?"}
qid4 = rpc("add_question", [session_key, sid, gid2, "en", q4_data, [], [], []]).get("result")

# Add answers for Q4
rpc("add_answer", [session_key, sid, qid4, "I1", "en", "Under $30,000"])
rpc("add_answer", [session_key, sid, qid4, "I2", "en", "$30,000 - $60,000"])
rpc("add_answer", [session_key, sid, qid4, "I3", "en", "Over $60,000"])

# 6. Ensure initial state is clean (No public stats enabled)
# This is default behavior, but we can enforce it if needed via DB later in script if API lacks it.

rpc("release_session_key", [session_key])
print("Survey setup complete.")
PYEOF

# Record survey ID
SURVEY_ID=$(get_survey_id "Participatory Budgeting 2026")
echo "$SURVEY_ID" > /tmp/task_survey_id
echo "Survey ID: $SURVEY_ID"

# Prepare Firefox
echo "Launching Firefox..."
focus_firefox
# Navigate to survey list or dashboard
DISPLAY=:1 xdotool type "http://localhost/index.php/admin/survey/sa/view/surveyid/$SURVEY_ID"
DISPLAY=:1 xdotool key Return
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="