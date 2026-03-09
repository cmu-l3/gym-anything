#!/bin/bash
set -e
echo "=== Setting up Panel Integration Task ==="

source /workspace/scripts/task_utils.sh

# Wait for LimeSurvey API
wait_for_limesurvey_api() {
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost/index.php/admin/remotecontrol')" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

wait_for_limesurvey_api || echo "Warning: API check failed, proceeding anyway..."

# Create the survey via Python API to ensure clean state
python3 << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"
ADMIN_USER = "admin"
ADMIN_PASS = "Admin123!"

def api_req(method, params, req_id=1):
    data = json.dumps({"method": method, "params": params, "id": req_id}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.loads(response.read())
    except Exception as e:
        return {"error": str(e)}

# 1. Get Session Key
resp = api_req("get_session_key", [ADMIN_USER, ADMIN_PASS])
session_key = resp.get("result")

if not session_key or "error" in str(session_key).lower():
    print("Failed to get session key")
    sys.exit(1)

# 2. Cleanup existing surveys with same title
surveys = api_req("list_surveys", [session_key]).get("result", [])
target_title = "Enterprise Cloud Adoption 2024"
if isinstance(surveys, list):
    for s in surveys:
        if s.get("surveyls_title") == target_title:
            print(f"Deleting existing survey {s.get('sid')}")
            api_req("delete_survey", [session_key, s.get("sid")])

# 3. Create Survey
print(f"Creating survey: {target_title}")
sid_resp = api_req("add_survey", [session_key, 0, target_title, "en", "G"])
sid = sid_resp.get("result")
print(f"Created Survey ID: {sid}")

# 4. Add Group
gid_resp = api_req("add_group", [session_key, sid, "Screening", "Initial screening questions"])
gid = gid_resp.get("result")

# 5. Add Question Q01 (Yes/No)
q_data = {
    "title": "Q01",
    "type": "Y", # Yes/No question type
    "mandatory": "Y",
    "question_order": 1
}
# Note: JSON-RPC add_question signature varies by version, this is a standard attempt
# add_question(sSessionKey, iSurveyID, iGroupID, sQuestionCode, sQuestionText, sHelp) is older
# We try to inject structure or use add_question properties
q_text = "Are you the primary decision-maker for IT infrastructure?"
q_help = "Select one"

# Attempt to create question
# add_question(session, sid, gid, title, text, help)
# Note: Type is set via update_question usually or import, but let's try direct add if supported
# or use `add_question` standard signature and then `update_question_properties`

qid_resp = api_req("add_question", [session_key, sid, gid, "Q01", q_text, q_help])
qid = qid_resp.get("result")
print(f"Created Question ID: {qid}")

# Update question properties to set type to Yes/No ('Y')
api_req("set_question_properties", [session_key, qid, {"type": "Y", "mandatory": "Y"}])

# Release session
api_req("release_session_key", [session_key])
print("Setup complete")
PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Ensure Firefox is open and focused
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
else
    focus_firefox
    DISPLAY=:1 xdotool key F5
fi

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Task setup complete ==="